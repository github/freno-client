require 'test_helper'

class Freno::ClientTest < Freno::Client::Test
  def test_that_it_has_a_version_number
    refute_nil ::Freno::Client::VERSION
  end

  def test_check_read_succeeds
    client = stubbed_client do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |env| [200, {}, nil] }
    end

    assert client.check_read(threshold: 0.5) == :ok
    assert client.check_read(threshold: 0.5) == 200
    assert client.check_read?(threshold: 0.5)
  end

  def test_check_read_fails
    client = stubbed_client do |stub|
      stub.head("/check-read/github/mysql/main/0.5") { |env| [500, {}, nil] }
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

    ex = assert_raises Faraday::TimeoutError do
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
end
