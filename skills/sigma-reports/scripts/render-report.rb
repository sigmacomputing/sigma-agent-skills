#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'optparse'
require 'uri'

options = {
  layout: 'portrait',
  dpi: 96,
  timeout: 180
}
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/render-report.rb REPORT_ID OUTPUT_DIR [options]'
  opts.on('--layout NAME', %w[portrait landscape], 'PDF layout (default: portrait)') { |value| options[:layout] = value }
  opts.on('--page-id ID', 'Export one report page instead of the complete report') { |value| options[:page_id] = value }
  opts.on('--dpi N', Integer, 'PNG raster DPI (default: 96)') { |value| options[:dpi] = value }
  opts.on('--timeout N', Integer, 'Export timeout seconds (default: 180)') { |value| options[:timeout] = value }
end
parser.parse!
report_id = ARGV.shift
output_dir = ARGV.shift
abort parser.to_s unless report_id && output_dir && ARGV.empty?

base_url = ENV['SIGMA_BASE_URL']&.sub(%r{/$}, '')
token = ENV['SIGMA_API_TOKEN']
abort 'SIGMA_BASE_URL is required' unless base_url
abort 'SIGMA_API_TOKEN is required' unless token

def request(base_url, token, method, path, body: nil, accept: 'application/json')
  uri = URI("#{base_url}#{path}")
  klass = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post
  }.fetch(method)
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Accept'] = accept
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump(body)
  end
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 120) do |http|
    http.request(req)
  end
end

body = {'format' => {'type' => 'pdf', 'layout' => options[:layout]}}
body['pageId'] = options[:page_id] if options[:page_id]
response = request(
  base_url, token, :post, "/v2/reports/#{report_id}/export", body: body
)
unless response.code.to_i.between?(200, 299)
  abort "report export failed: HTTP #{response.code}\n#{response.body}"
end
payload = JSON.parse(response.body)
query_id = payload['queryId'] || payload['exportId']
abort "report export response had no queryId: #{payload.inspect}" unless query_id

deadline = Time.now + options[:timeout]
pdf = nil
loop do
  response = request(
    base_url, token, :get, "/v2/query/#{query_id}/download", accept: '*/*'
  )
  code = response.code.to_i
  if code == 200 && !response.body.to_s.empty?
    pdf = response.body
    break
  end
  unless [200, 202, 204, 404, 409, 425, 500, 502, 503, 504].include?(code)
    abort "report download failed: HTTP #{response.code}\n#{response.body}"
  end
  abort "report export timed out after #{options[:timeout]} seconds" if Time.now >= deadline

  sleep 2
end

FileUtils.mkdir_p(output_dir)
pdf_path = File.join(output_dir, 'report.pdf')
File.binwrite(pdf_path, pdf)
puts "wrote #{pdf_path} (#{pdf.bytesize} bytes)"

unless system('sh', '-c', 'command -v pdftoppm >/dev/null 2>&1')
  warn 'pdftoppm is not installed; PDF saved but PNG pages were not rendered'
  exit 0
end

prefix = File.join(output_dir, 'page')
unless system('pdftoppm', '-png', '-r', options[:dpi].to_s, pdf_path, prefix)
  abort 'pdftoppm failed to rasterize the report'
end
page_count = Dir["#{prefix}-*.png"].length
puts "rendered #{page_count} PNG page(s) at #{options[:dpi]} DPI"
