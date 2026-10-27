# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class FrenoClientTransportCircuitBreakerTest < ClientTest
  class MemoryCircuitBreaker
    attr_reader :successes, :failures
    attr_accessor :allow_requests

    def initialize(allow_requests: true)
      @allow_requests = allow_requests
      @successes = 0
      @failures = 0
    end

    def allow_request?
      allow_requests
    end

    def success
      @successes += 1
    end

    def failure
      @failures += 1
    end
  end

  class SingleFailureCircuitBreaker < MemoryCircuitBreaker
    def failure
      super
      self.allow_requests = false
    end
  end

  class KwargsRecorder
    attr_accessor :request
    attr_reader :kwargs

    def perform(**kwargs)
      @kwargs = kwargs
      request.perform(**kwargs)
    end
  end

  class ResponseValidator < Faraday::Middleware
    def call(env)
      @app.call(env).on_complete { |response_env| on_complete(response_env) }
    end

    def on_complete(env)
      raise Freno::Error, "rejected response" if env.status == 417
      raise Freno::Error, "failed response" if env.status == 500
    end
  end

  class StatusRetry < Faraday::Middleware
    def call(env)
      response = @app.call(env)
      response.status == 500 ? @app.call(env) : response
    end
  end

  class ExceptionRetry < Faraday::Middleware
    def call(env)
      @app.call(env)
    rescue Faraday::TimeoutError
      @app.call(env)
    end
  end

  class NestedBeforeForward < Faraday::Middleware
    def initialize(app, connection)
      super(app)
      @connection = connection
    end

    def call(env)
      @connection.call.head("/nested") unless env.url.path == "/nested"
      @app.call(env)
    end
  end

  class NestedClientCall < Faraday::Middleware
    def initialize(app, client, results)
      super(app)
      @client = client
      @results = results
    end

    def call(env)
      @results << @client.call.check_read?(threshold: 0.5) unless env.url.path.start_with?("/check-read/")
      @app.call(env)
    end
  end

  class CallbackError < StandardError; end
  class ExistingFrenoError < Freno::Error; end

  class CallbackErrorBreaker < MemoryCircuitBreaker
    def success
      raise CallbackError, "callback failed"
    end
  end

  class StatusError < StandardError
    attr_reader :response_status

    def initialize(response_status)
      @response_status = response_status
      super("status error")
    end
  end

  class ConcurrencyCheckingBreaker < MemoryCircuitBreaker
    attr_reader :violations

    def initialize
      super
      @guard = Mutex.new
      @active = false
      @violations = 0
    end

    def allow_request?
      check_concurrency { super }
    end

    def success
      check_concurrency { super }
    end

    private

    def check_concurrency
      @guard.synchronize do
        @violations += 1 if @active
        @active = true
      end
      sleep 0.001
      yield
    ensure
      @guard.synchronize { @active = false }
    end
  end

  def test_disabled_breaker_preserves_existing_behavior
    recorder = KwargsRecorder.new
    client = stubbed_client do |stub|
      stub.head("/check/github/mysql/main") { [200, {}, nil] }
    end
    client.decorate(:check, with: recorder)

    assert_predicate client, :check?
    refute_includes recorder.kwargs, :transport_circuit_breaker
  end

  def test_disabled_client_wraps_existing_freno_errors
    client = stubbed_client do |stub|
      stub.head("/check/github/mysql/main") { raise ExistingFrenoError, "existing error" }
    end

    error = assert_raises(Freno::Error) { client.check }

    assert_instance_of Freno::Error, error
    assert_instance_of ExistingFrenoError, error.cause
  end

  def test_classifies_http_failures_and_successes
    breaker = MemoryCircuitBreaker.new
    statuses = [500, 408, 200]
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") { [statuses.shift, {}, nil] }
    end

    3.times { client.check }

    assert_equal 1, breaker.successes
    assert_equal 2, breaker.failures
  end

  def test_failure_can_open_the_injected_breaker_for_the_shared_client
    breaker = SingleFailureCircuitBreaker.new
    check_read_calls = 0
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") { [500, {}, nil] }
      stub.head("/check-read/github/mysql/main/0.5") do
        check_read_calls += 1
        [200, {}, nil]
      end
    end

    refute_predicate client, :check?
    assert_raises(Freno::Client::TransportCircuitBreaker::CircuitOpen) do
      client.check_read?(threshold: 0.5)
    end
    assert_equal 0, check_read_calls
  end

  def test_endpoint_reachable_responses_are_successes
    breaker = MemoryCircuitBreaker.new
    statuses = [200, 404, 417, 429, 422]
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") { [statuses.shift, {}, nil] }
    end

    results = Array.new(5) { client.check }

    assert_equal [200, 404, 417, 429, 422], results.map(&:code)
    assert_equal 5, breaker.successes
    assert_equal 0, breaker.failures
  end

  def test_transport_errors_are_failures
    [Faraday::ConnectionFailed, Faraday::TimeoutError, Errno::ECONNRESET].each do |error_class|
      breaker = MemoryCircuitBreaker.new
      client = breaker_client(breaker) do |stub|
        stub.head("/check/github/mysql/main") { raise error_class, "unavailable" }
      end

      assert_raises(Freno::Error) { client.check }
      assert_equal 1, breaker.failures
      assert_equal 0, breaker.successes
    end
  end

  def test_faraday_status_errors_are_classified_by_response_status
    breaker = MemoryCircuitBreaker.new
    errors = [
      Faraday::ServerError.new("server error", status: 503),
      Faraday::ClientError.new("client error", status: 404)
    ]
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") do
        raise errors.shift
      end
    end

    2.times { assert_raises(Freno::Error) { client.check } }

    assert_equal 1, breaker.failures
    assert_equal 1, breaker.successes
  end

  def test_status_retry_records_only_the_final_success
    breaker = MemoryCircuitBreaker.new
    statuses = [500, 200]
    client = middleware_client(breaker, StatusRetry) do |stub|
      stub.head("/check/github/mysql/main") { [statuses.shift, {}, nil] }
    end

    assert_predicate client, :check?
    assert_equal 1, breaker.successes
    assert_equal 0, breaker.failures
  end

  def test_exception_retry_records_only_the_final_success
    breaker = MemoryCircuitBreaker.new
    calls = 0
    client = middleware_client(breaker, ExceptionRetry) do |stub|
      stub.head("/check/github/mysql/main") do
        calls += 1
        raise Faraday::TimeoutError if calls == 1

        [200, {}, nil]
      end
    end

    assert_predicate client, :check?
    assert_equal 1, breaker.successes
    assert_equal 0, breaker.failures
  end

  def test_nested_success_does_not_replace_outer_failure
    breaker = MemoryCircuitBreaker.new
    client = nested_request_client(breaker, outer_status: 500, nested_status: 200)

    refute_predicate client, :check?
    assert_equal 0, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_nested_failure_does_not_replace_outer_success
    breaker = MemoryCircuitBreaker.new
    client = nested_request_client(breaker, outer_status: 200, nested_status: 500)

    assert_predicate client, :check?
    assert_equal 1, breaker.successes
    assert_equal 0, breaker.failures
  end

  def test_nested_success_before_outer_forward_does_not_replace_outer_failure
    breaker = MemoryCircuitBreaker.new
    client = pre_forward_nested_request_client(breaker, outer_status: 500, nested_status: 200)

    refute_predicate client, :check?
    assert_equal 0, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_nested_failure_before_outer_forward_does_not_replace_outer_success
    breaker = MemoryCircuitBreaker.new
    client = pre_forward_nested_request_client(breaker, outer_status: 200, nested_status: 500)

    assert_predicate client, :check?
    assert_equal 1, breaker.successes
    assert_equal 0, breaker.failures
  end

  def test_synchronous_nested_client_call_restores_the_outer_context
    breaker = MemoryCircuitBreaker.new
    nested_results = []
    client = nested_client_call_client(breaker, nested_results)

    refute_predicate client, :check?
    assert_equal [true], nested_results
    assert_equal 1, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_response_validators_do_not_hide_raw_status_accounting
    breaker = MemoryCircuitBreaker.new
    statuses = [417, 500]
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.head("/check/github/mysql/main") { [statuses.shift, {}, nil] }
    end
    faraday = Faraday.new do |builder|
      builder.use(ResponseValidator)
      builder.adapter(:test, stubs)
    end
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app = :github
      freno.enable_transport_circuit_breaker(circuit_breaker: breaker)
    end

    2.times { assert_raises(Freno::Error) { client.check } }

    assert_equal 1, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_wrapped_freno_error_without_a_status_is_a_failure
    breaker = MemoryCircuitBreaker.new
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") do
        raise Freno::Error, Faraday::TimeoutError.new("timeout")
      end
    end

    assert_raises(Freno::Error) { client.check }
    assert_equal 0, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_callback_error_is_preserved_without_opposite_accounting
    breaker = CallbackErrorBreaker.new
    error = CallbackError.new("callback failed")
    breaker.expects(:success).raises(error)
    adapter = transport_adapter(breaker)

    raised = assert_raises(CallbackError) do
      adapter.call { Struct.new(:status).new(200) }
    end

    assert_same error, raised
    assert_equal 0, breaker.failures
  end

  def test_invalid_returned_statuses_are_failures
    breaker = MemoryCircuitBreaker.new
    adapter = transport_adapter(breaker)

    [nil, 0].each do |status|
      adapter.call { Struct.new(:status).new(status) }
    end

    assert_equal 0, breaker.successes
    assert_equal 2, breaker.failures
  end

  def test_invalid_exception_statuses_are_failures
    breaker = MemoryCircuitBreaker.new
    adapter = transport_adapter(breaker)

    [nil, 0].each do |status|
      assert_raises(StatusError) { adapter.call { raise StatusError, status } }
    end

    assert_equal 0, breaker.successes
    assert_equal 2, breaker.failures
  end

  def test_rejection_raises_and_prevents_network_calls_by_default
    breaker = MemoryCircuitBreaker.new(allow_requests: false)
    calls = 0
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") do
        calls += 1
        [200, {}, nil]
      end
    end

    assert_raises(Freno::Client::TransportCircuitBreaker::CircuitOpen) { client.check }
    assert_equal 0, calls
  end

  def test_rejection_returns_timeout_result_when_timeouts_do_not_raise
    breaker = MemoryCircuitBreaker.new(allow_requests: false)
    calls = 0
    client = breaker_client(breaker, raise_on_timeout: false) do |stub|
      stub.head("/check/github/mysql/main") do
        calls += 1
        [200, {}, nil]
      end
    end

    assert_operator client.check, :==, :request_timeout
    refute_predicate client, :check?
    assert_equal 0, calls
  end

  def test_open_breaker_prevents_a_throttled_write
    breaker = MemoryCircuitBreaker.new(allow_requests: false)
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") { [200, {}, nil] }
    end
    throttler = Freno::Throttler.new(client: client, app: :github)
    write_performed = false

    assert_raises(Freno::Throttler::ClientError) do
      throttler.throttle(:main) { write_performed = true }
    end
    refute write_performed
  end

  def test_serializes_access_to_the_injected_breaker
    breaker = ConcurrencyCheckingBreaker.new
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") { [200, {}, nil] }
    end

    threads = Array.new(10) { Thread.new { client.check } }
    threads.each(&:join)

    assert_equal 0, breaker.violations
    assert_equal 10, breaker.successes
  end

  def test_concurrent_request_statuses_do_not_cross_contexts
    breaker = MemoryCircuitBreaker.new
    ready = Queue.new
    release = Queue.new
    client = breaker_client(breaker) do |stub|
      stub.head("/check/github/mysql/main") do
        ready << true
        release.pop
        [500, {}, nil]
      end
      stub.head("/check-read/github/mysql/main/0.5") do
        ready << true
        release.pop
        [200, {}, nil]
      end
    end

    checks = [
      Thread.new { client.check? },
      Thread.new { client.check_read?(threshold: 0.5) }
    ]
    2.times { ready.pop }
    2.times { release << true }

    assert_equal [false, true], checks.map(&:value)
    assert_equal 1, breaker.successes
    assert_equal 1, breaker.failures
  end

  def test_rejects_an_invalid_breaker
    error = assert_raises(ArgumentError) do
      stubbed_client.enable_transport_circuit_breaker(circuit_breaker: Object.new)
    end

    assert_equal "circuit breaker must respond to allow_request?, success, failure", error.message
  end

  def test_rejects_duplicate_configuration
    client = stubbed_client
    client.enable_transport_circuit_breaker(circuit_breaker: MemoryCircuitBreaker.new)

    error = assert_raises(ArgumentError) do
      client.enable_transport_circuit_breaker(circuit_breaker: MemoryCircuitBreaker.new)
    end

    assert_equal "transport circuit breaker is already enabled", error.message
  end

  def test_rejects_configuration_after_the_first_faraday_request
    faraday = stubbed_faraday do |stub|
      stub.get("/first") { [200, {}, nil] }
    end
    faraday.get("/first")
    client = Freno::Client.new(faraday)

    error = assert_raises(ArgumentError) do
      client.enable_transport_circuit_breaker(circuit_breaker: MemoryCircuitBreaker.new)
    end

    assert_equal "transport circuit breaker must be enabled before the first Faraday request", error.message
  end

  def test_request_subclass_can_be_loaded_independently
    script = <<~RUBY
      require "freno/client/requests/check"

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.head("/check/github/mysql/main") { raise Faraday::TimeoutError }
      end
      faraday = Faraday.new { |builder| builder.adapter(:test, stubs) }
      request = Freno::Client::Requests::Check.new(
        faraday: faraday,
        app: "github",
        store_type: "mysql",
        store_name: "main"
      )

      begin
        request.perform
      rescue Freno::Error
        exit 0
      end

      exit 1
    RUBY
    _output, error, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path('../../../lib', __dir__)}",
      "-e",
      script
    )

    assert_predicate status, :success?, error
  end

  private

  def breaker_client(breaker, raise_on_timeout: true, &block)
    client = stubbed_client(&block)
    configure_breaker(client, breaker, raise_on_timeout: raise_on_timeout)
  end

  def middleware_client(breaker, middleware, &block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    faraday = Faraday.new do |builder|
      builder.use(middleware)
      builder.adapter(:test, stubs)
    end
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app = :github
    end
    configure_breaker(client, breaker)
  end

  def configure_breaker(client, breaker, raise_on_timeout: true)
    client.options[:raise_on_timeout] = raise_on_timeout
    client.enable_transport_circuit_breaker(circuit_breaker: breaker)
    client
  end

  def transport_adapter(breaker)
    faraday = stubbed_faraday
    Freno::Client::TransportCircuitBreaker.new(
      circuit_breaker: breaker,
      faraday: faraday
    )
  end

  def nested_request_client(breaker, outer_status:, nested_status:)
    faraday = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.head("/nested") { [nested_status, {}, nil] }
      stub.head("/check/github/mysql/main") do
        faraday.head("/nested")
        [outer_status, {}, nil]
      end
    end
    faraday = Faraday.new { |builder| builder.adapter(:test, stubs) }
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app = :github
    end
    configure_breaker(client, breaker)
  end

  def pre_forward_nested_request_client(breaker, outer_status:, nested_status:)
    faraday = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.head("/nested") { [nested_status, {}, nil] }
      stub.head("/check/github/mysql/main") { [outer_status, {}, nil] }
    end
    faraday = Faraday.new do |builder|
      builder.use(NestedBeforeForward, -> { faraday })
      builder.adapter(:test, stubs)
    end
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app = :github
    end
    configure_breaker(client, breaker)
  end

  def nested_client_call_client(breaker, nested_results)
    client = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { [200, {}, nil] }
      stub.head("/check/github/mysql/main") { [500, {}, nil] }
    end
    faraday = Faraday.new do |builder|
      builder.use(NestedClientCall, -> { client }, nested_results)
      builder.adapter(:test, stubs)
    end
    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app = :github
    end
    configure_breaker(client, breaker)
  end
end
