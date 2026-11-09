#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class ListTableColumnsTest < Minitest::Test
  HELPER = File.expand_path('list-table-columns.sh', __dir__)

  def columns(prefix, count)
    count.times.map do |index|
      {
        'name' => "#{prefix}_#{index + 1}",
        'type' => {'type' => 'text'},
        'visibility' => 'included'
      }
    end
  end

  def write_json(path, payload)
    File.write(path, JSON.generate(payload))
  end

  def fake_curl(dir)
    path = File.join(dir, 'curl')
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      printf '%s\\n' "$*" >> "$CALL_LOG"
      case "$*" in
        *"pageToken=$EXPECTED_TOKEN"*) cat "$PAGE_2" ;;
        *) cat "$PAGE_1" ;;
      esac
    SH
    File.chmod(0o755, path)
    path
  end

  def run_helper(dir, page_1:, page_2:, expected_token: 'token-2')
    page_1_path = File.join(dir, 'page-1.json')
    page_2_path = File.join(dir, 'page-2.json')
    log_path = File.join(dir, 'calls.log')
    write_json(page_1_path, page_1)
    write_json(page_2_path, page_2)
    fake_curl(dir)
    env = {
      'PATH' => "#{dir}:#{ENV.fetch('PATH')}",
      'SIGMA_BASE_URL' => 'https://api.sigmacomputing.com',
      'SIGMA_API_TOKEN' => 'test-token',
      'PAGE_1' => page_1_path,
      'PAGE_2' => page_2_path,
      'CALL_LOG' => log_path,
      'EXPECTED_TOKEN' => expected_token
    }
    stdout, stderr, status = Open3.capture3(env, 'bash', HELPER, 'inode-test-table')
    [stdout, stderr, status, File.exist?(log_path) ? File.read(log_path) : '']
  end

  def test_fetches_every_page_and_combines_entries
    Dir.mktmpdir('column-pagination') do |dir|
      page_1 = {'entries' => columns('first', 50), 'nextPageToken' => 'token-2'}
      page_2 = {'entries' => columns('second', 70)}
      stdout, stderr, status, calls = run_helper(dir, page_1: page_1, page_2: page_2)

      assert status.success?, stderr
      result = JSON.parse(stdout)
      assert_equal 120, result['totalCount']
      assert_equal 2, result['pageCount']
      assert_equal 'first_1', result['entries'].first['name']
      assert_equal 'second_70', result['entries'].last['name']
      assert_equal 2, calls.lines.length
      assert_includes calls.lines.first, 'pageSize=1000'
      assert_includes calls.lines.last, 'pageToken=token-2'
    end
  end

  def test_repeated_next_page_token_fails_instead_of_looping
    Dir.mktmpdir('column-pagination') do |dir|
      page_1 = {'entries' => columns('first', 1), 'nextPageToken' => 'token-2'}
      page_2 = {'entries' => columns('second', 1), 'nextPageToken' => 'token-2'}
      _stdout, stderr, status, calls = run_helper(dir, page_1: page_1, page_2: page_2)

      refute status.success?
      assert_includes stderr, 'repeated nextPageToken'
      assert_equal 2, calls.lines.length
    end
  end

  def test_invalid_response_fails_loudly
    Dir.mktmpdir('column-pagination') do |dir|
      page_1 = {'message' => 'not a column response'}
      page_2 = {'entries' => []}
      _stdout, stderr, status, calls = run_helper(dir, page_1: page_1, page_2: page_2)

      refute status.success?
      assert_includes stderr, 'did not contain an entries array'
      assert_equal 1, calls.lines.length
    end
  end
end
