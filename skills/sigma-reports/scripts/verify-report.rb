#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative 'lib/report_verifier'

report_id = ARGV.shift
abort 'Usage: ruby scripts/verify-report.rb REPORT_ID' unless report_id && ARGV.empty?

base_url = ENV['SIGMA_BASE_URL']&.sub(%r{/$}, '')
token = ENV['SIGMA_API_TOKEN']
abort 'SIGMA_BASE_URL is required' unless base_url
abort 'SIGMA_API_TOKEN is required' unless token

def request(base_url, token, path)
  uri = URI("#{base_url}#{path}")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Accept'] = 'application/json'
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 120) do |http|
    http.request(req)
  end
end

response = request(base_url, token, "/v2/reports/#{report_id}/elements")
unless response.code.to_i.between?(200, 299)
  abort "could not list report elements: HTTP #{response.code}\n#{response.body}"
end
payload = JSON.parse(response.body)
entries = payload['entries'] || []
failures = 0
queryable = 0
skipped = 0

entries.each do |element|
  element_id = element['elementId'] || element['id']
  name = element['name'] || element_id || '(unnamed)'
  next unless element_id

  response = request(
    base_url, token,
    "/v2/reports/#{report_id}/elements/#{element_id}/query"
  )
  if response.code.to_i == 404
    skipped += 1
    printf "  [skip] %-32s — non-queryable element\n", name
    next
  end
  unless response.code.to_i.between?(200, 299)
    failures += 1
    printf "  [FAIL] %-32s — query endpoint HTTP %s\n", name, response.code
    next
  end

  queryable += 1
  body = response.body.to_s
  sql = begin
    JSON.parse(body)['sql'].to_s
  rescue JSON::ParserError
    body
  end
  markers = ReportSpec::Verifier.compile_markers("#{body}\n#{sql}")
  if markers.empty?
    printf "  [ok]   %-32s\n", name
  else
    failures += 1
    printf "  [FAIL] %-32s — %s\n", name, markers.join('; ')
  end
end

puts
puts "#{queryable} query-backed element(s) checked; #{skipped} non-queryable element(s) skipped."
if failures.positive?
  warn "#{failures} report element(s) failed compile verification."
  exit 1
end

puts 'All query-backed report elements compile cleanly.'
