# frozen_string_literal: true

require "test_helper"

class Freno::ClientTest < Freno::Client::Test
  def test_that_it_has_a_version_number
    refute_nil ::Freno::Client::VERSION
  end

  def test_replication_delay
    client = stubbed_client do |stub|
      stub.get("/check/github/mysql/main") { |_env| [200, {}, <<-BODY] }
        {"StatusCode":200,"Value":0.025173,"Threshold":1,"Message":""}
      BODY
    end
    assert_in_delta 0.025173, client.replication_delay, 0.0000001
  end

  def test_check_succeeds
    client = stubbed_client do |stub|
      stub.head("/check/github/mysql/main") { |_env| [200, {}, nil] }
    end

    assert client.check == :ok
    assert client.check == 200
    assert client.check?
  end

  def test_check_fails
    client = stubbed_client do |stub|
      stub.head("/check/github/mysql/main") { |_env| [500, {}, nil] }
    end

    assert client.check == :internal_server_error
    assert client.check == 500
    refute client.check?
  end

  def test_check_read_succeeds
    client = stubbed_client do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
    end

    assert client.check_read(threshold: 0.5) == :ok
    assert client.check_read(threshold: 0.5) == 200
    assert client.check_read?(threshold: 0.5)
  end

  def test_check_read_fails
    client = stubbed_client do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [500, {}, nil] }
    end

    assert client.check_read(threshold: 0.5) == :internal_server_error
    assert client.check_read(threshold: 0.5) == 500
    refute client.check_read?(threshold: 0.5)
  end

  def test_check_read_times_out
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { raise Faraday::TimeoutError }
    end

    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name = :main
      freno.default_store_type = :mysql
      freno.default_app        = :github
    end

    ex = assert_raises Freno::Error do
      client.check_read(threshold: 0.5) == :request_timeout
    end

    assert_equal "timeout", ex.message
  end

  def test_check_read_times_out_with_raise_on_timeout_set_to_false
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { raise Faraday::TimeoutError }
    end

    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name         = :main
      freno.default_store_type         = :mysql
      freno.default_app                = :github
      freno.options[:raise_on_timeout] = false
    end

    assert client.check_read(threshold: 0.5) == :request_timeout
  end

  class Decorator
    attr_accessor :request

    def initialize(memo, word)
      @memo = memo
      @word = word
    end

    def perform(**kwargs)
      @memo << @word
      request.perform(**kwargs)
    end
  end

  def test_decorators_can_be_applied_to_a_single_request
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
      stub.head("/check/github/mysql/main") { |_env| [200, {}, nil] }
    end

    memo = []

    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name         = :main
      freno.default_store_type         = :mysql
      freno.default_app                = :github
      freno.decorate(:check_read, with: [Decorator.new(memo, "first"), Decorator.new(memo, "second")])
    end

    assert client.check_read(threshold: 0.5) == :ok
    assert_equal %w(first second), memo

    memo.clear
    assert client.check == :ok
    assert_equal [], memo
  end

  def test_decorators_can_be_applied_to_all_requests
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
      stub.head("/check/github/mysql/main") { |_env| [200, {}, nil] }
    end

    memo = []

    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name         = :main
      freno.default_store_type         = :mysql
      freno.default_app                = :github
      freno.decorate(:all, with: [Decorator.new(memo, "first"), Decorator.new(memo, "second")])
    end

    assert client.check_read(threshold: 0.5) == :ok
    assert_equal %w(first second), memo

    memo.clear
    assert client.check == :ok
    assert_equal %w(first second), memo
  end

  def test_decorator_instance_cannot_be_reused
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
      stub.head("/check/github/mysql/main") { |_env| [200, {}, nil] }
    end

    memo = []
    decorator = Decorator.new(memo, "only_one")
    duplicate_decorator = decorator

    ex = assert_raises Freno::Client::DecorationError do
      Freno::Client.new(faraday) do |freno|
        freno.default_store_name         = :main
        freno.default_store_type         = :mysql
        freno.default_app                = :github
        freno.decorate(:all, with: [decorator, duplicate_decorator])
      end
    end
    assert_match "Cannot reuse decorator instance", ex.message
  end

  def test_single_decorator_instance_can_be_provided
    faraday = stubbed_faraday do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |_env| [200, {}, nil] }
      stub.head("/check/github/mysql/main") { |_env| [200, {}, nil] }
    end

    memo = []
    decorator = Decorator.new(memo, "only")

    client = Freno::Client.new(faraday) do |freno|
      freno.default_store_name         = :main
      freno.default_store_type         = :mysql
      freno.default_app                = :github
      freno.decorate(:all, with: decorator)
    end

    assert client.check_read(threshold: 0.5) == :ok
    assert_equal %w(only), memo

    memo.clear
    assert client.check == :ok
    assert_equal %w(only), memo
  end
end
