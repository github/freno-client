# frozen_string_literal: true

require "test_helper"

class FrenoClientRequestsCheckReadTest < ClientTest
  include Freno::Client::Requests

  def test_preconditions_require_an_app_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      CheckRead.new(faraday: stubbed_faraday, app: nil, store_type: "mysql", store_name: "main", threshold: 0.5)
    end

    assert_equal "app should be present", ex.message
  end

  def test_preconditions_require_store_type_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      CheckRead.new(faraday: stubbed_faraday, app: "github", store_type: nil, store_name: "main", threshold: 0.5)
    end

    assert_equal "store_type should be present", ex.message
  end

  def test_preconditions_require_store_name_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      CheckRead.new(faraday: stubbed_faraday, app: "github", store_type: "mysql", store_name: nil, threshold: 0.5)
    end

    assert_equal "store_name should be present", ex.message
  end

  def test_perform_calls_the_proper_service_endpoint_and_succeeds
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)
    response = request.perform

    assert_equal :ok, response.meaning
    assert_equal 200, response.code
  end

  def test_perform_calls_the_proper_service_endpoint_with_low_priority_and_succeeds
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5?p=low") { |_env| [200, {}, nil] }
    end

    request = CheckRead.new(
      faraday: faraday,
      app: "github",
      store_type: "mysql",
      store_name: "main",
      threshold: 0.5,
      options: { low_priority: true }
    )
    response = request.perform

    assert_equal :ok, response.meaning
    assert_equal 200, response.code
  end

  def test_perform_calls_the_proper_service_endpoint_and_fails_due_to_not_found
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [404, {}, nil] }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)
    response = request.perform

    assert_operator response, :==, :not_found
    assert_operator response, :==, 404

    assert_equal :not_found, response.meaning
    assert_equal 404, response.code
  end

  def test_perform_calls_the_proper_service_endpoint_and_fails_due_to_expectation_failed
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [417, {}, nil] }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)
    response = request.perform

    assert_equal :expectation_failed, response.meaning
    assert_equal 417, response.code
  end

  def test_perform_calls_the_proper_service_endpoint_and_fails_due_to_too_many_requests
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [429, {}, nil] }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)
    response = request.perform

    assert_equal :too_many_requests, response.meaning
    assert_equal 429, response.code
  end

  def test_perform_calls_the_proper_service_endpoint_and_fails_due_to_internal_server_error
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [500, {}, nil] }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)
    response = request.perform

    assert_equal :internal_server_error, response.meaning
    assert_equal 500, response.code
  end

  def test_timeouts
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { raise Faraday::TimeoutError }
    end

    request = CheckRead.new(
      faraday: faraday,
      app: "github",
      store_type: "mysql",
      store_name: "main",
      threshold: 0.5,
      options: { raise_on_timeout: false }
    )
    response = request.perform

    assert_equal :request_timeout, response.meaning
    assert_equal 408, response.code
  end

  def test_timeouts_with_raise_on_timeout_set_to_false
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { raise Faraday::TimeoutError }
    end

    request = CheckRead.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", threshold: 0.5)

    ex = assert_raises Freno::Error do
      request.perform
    end

    assert_equal "timeout", ex.message
  end
end
