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
end
