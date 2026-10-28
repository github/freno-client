# frozen_string_literal: true

require "test_helper"

class FrenoThrottlerRetryHeaderTest < ThrottlerTest
  CHECK_PATH = "/check/github/mysql/mysqla"
  OTHER_CHECK_PATH = "/check/github/mysql/mysqlb"

  def test_first_check_never_has_the_retry_header
    responses = { CHECK_PATH => [200] }
    sent_headers = throttle_with(responses)

    assert_equal [nil], sent_headers[CHECK_PATH]
  end

  def test_recheck_after_throttled_answer_has_no_retry_header
    responses = { CHECK_PATH => [417, 429, 200] }
    sent_headers = throttle_with(responses)

    assert_equal [nil, nil, nil], sent_headers[CHECK_PATH]
  end

  def test_recheck_after_client_timeout_has_the_retry_header
    responses = { CHECK_PATH => [:timeout, 200] }
    sent_headers = throttle_with(responses)

    assert_equal [nil, "true"], sent_headers[CHECK_PATH]
  end

  def test_recheck_after_408_has_the_retry_header
    responses = { CHECK_PATH => [408, 200] }
    sent_headers = throttle_with(responses)

    assert_equal [nil, "true"], sent_headers[CHECK_PATH]
  end

  def test_retry_header_is_dropped_once_a_check_gets_an_answer
    responses = { CHECK_PATH => [:timeout, 417, 200] }
    sent_headers = throttle_with(responses)

    assert_equal [nil, "true", nil], sent_headers[CHECK_PATH]
  end

  def test_retry_header_applies_only_to_the_store_that_timed_out
    responses = { CHECK_PATH => [:timeout, 200], OTHER_CHECK_PATH => [200] }
    sent_headers = throttle_with(responses, store_names: %i[mysqla mysqlb])

    assert_equal [nil, "true"], sent_headers[CHECK_PATH]
    assert_equal [nil], sent_headers[OTHER_CHECK_PATH]
  end

  def test_retry_header_does_not_leak_into_the_next_throttle_call
    responses = { CHECK_PATH => [:timeout, 200, 200] }
    sent_headers = {}
    throttler = build_throttler(responses, sent_headers)

    throttler.throttle(:mysqla) { nil }
    throttler.throttle(:mysqla) { nil }

    assert_equal [nil, "true", nil], sent_headers[CHECK_PATH]
  end

  def test_retry_header_is_not_sent_unless_enabled
    responses = { CHECK_PATH => [:timeout, 408, 200] }
    sent_headers = throttle_with(responses, mark_timeout_retries: false)

    assert_equal [nil, nil, nil], sent_headers[CHECK_PATH]
  end

  def test_mark_timeout_retries_defaults_to_false
    throttler = Freno::Throttler.new(client: sample_client, app: :github)

    refute throttler.mark_timeout_retries
  end

  private

  def throttle_with(responses, store_names: :mysqla, mark_timeout_retries: true)
    sent_headers = {}
    throttler = build_throttler(responses, sent_headers, mark_timeout_retries: mark_timeout_retries)
    block_called = false

    throttler.throttle(store_names) do
      block_called = true
    end

    assert block_called, "block should have been called"
    sent_headers
  end

  def build_throttler(responses, sent_headers, mark_timeout_retries: true)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      responses.each do |path, outcomes|
        remaining = outcomes.dup
        stub.head(path) do |env|
          (sent_headers[path] ||= []) << env.request_headers[Freno::Client::Request::RETRY_HEADER]
          outcome = remaining.shift
          raise Faraday::TimeoutError, "timed out" if outcome == :timeout

          [outcome, {}, ""]
        end
      end
    end
    faraday = Faraday.new { |builder| builder.adapter :test, stubs }
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_type = :mysql
      freno.options[:raise_on_timeout] = false
    end

    throttler = Freno::Throttler.new(
      client: client,
      app: :github,
      wait_seconds: 1,
      max_wait_seconds: 30,
      mark_timeout_retries: mark_timeout_retries
    )
    throttler.stubs(:wait)
    throttler
  end
end
