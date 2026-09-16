#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'lib/report_spec_validator'

mode = :create
parser = OptionParser.new do |options|
  options.banner = 'Usage: ruby scripts/validate-spec.rb [--mode create|update] REPORT_SPEC.json'
  options.on('--mode MODE', %w[create update], 'Envelope mode (default: create)') { |value| mode = value.to_sym }
end

parser.parse!
path = ARGV.shift
abort parser.to_s unless path && ARGV.empty?

begin
  payload = JSON.parse(File.read(path))
rescue Errno::ENOENT
  warn "ERROR: file not found: #{path}"
  exit 2
rescue JSON::ParserError => e
  warn "ERROR: invalid JSON: #{e.message}"
  exit 2
end

result = ReportSpec::Validator.new(payload, mode: mode).validate
result.warnings.each { |warning| warn "WARN: #{warning}" }
result.errors.each { |error| warn "ERROR: #{error}" }

if result.valid?
  puts "PASS: report #{mode} representation is locally valid (#{result.warnings.length} warning(s))"
  exit 0
end

warn "FAIL: #{result.errors.length} error(s), #{result.warnings.length} warning(s)"
exit 1
