# frozen_string_literal: true

require "test_helper"

class Freno::Client::Requests::CheckTest < Freno::Client::Test
  include Freno::Client::Requests

  def test_preconditions_require_an_app_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      Check.new(faraday: stubbed_faraday, app: nil, store_type: "mysql", store_name: "main")
    end

    assert_equal "app should be present", ex.message
  end

  def test_preconditions_require_store_type_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      Check.new(faraday: stubbed_faraday, app: "github", store_type: nil, store_name: "main")
    end

    assert_equal "store_type should be present", ex.message
  end

  def test_preconditions_require_store_name_to_be_present
    ex = assert_raises Freno::Client::Preconditions::PreconditionNotMet do
      Check.new(faraday: stubbed_faraday, app: "github", store_type: "mysql", store_name: nil)
    end

    assert_equal "store_name should be present", ex.message
  end

  def test_perform_calls_the_proper_service_endpoint_and_fails
    faraday = stubbed_faraday do |stub|
      stub.head("/check/github/mysql/main") { |_env| [417, {}, <<-BODY] }
        {"StatusCode":417, "Value":0, "Threshold":0, "Message": "App denied"}
      BODY
    end

    request = Check.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main")
    response = request.perform

    assert_equal :expectation_failed,  response.meaning
    assert_equal 417, response.code
    assert_equal({ "StatusCode" => 417, "Value" => 0, "Threshold" => 0, "Message" => "App denied" }, response.body)
  end

  def test_perform_calls_the_proper_service_endpoint_and_succeeds
    faraday = stubbed_faraday do |stub|
      stub.head("/check/github/mysql/main") { |_env| [200, {}, <<-BODY] }
        {"StatusCode":200, "Value":0.025075, "Threshold":1, "Message":""}
      BODY
    end

    request = Check.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main")
    response = request.perform

    assert_equal :ok, response.meaning
    assert_equal 200, response.code
    assert_equal({ "StatusCode" => 200, "Value" => 0.025075, "Threshold" => 1, "Message" => "" }, response.body)
  end

  def test_perform_calls_the_proper_service_endpoint_with_low_priority_and_succeeds
    faraday = stubbed_faraday do |stub|
      stub.head("/check/github/mysql/main?p=low") { |_env| [200, {}, <<-BODY] }
        {"StatusCode":200, "Value":0.025075, "Threshold":1, "Message":""}
      BODY
    end

    request = Check.new(faraday: faraday, app: "github", store_type: "mysql", store_name: "main", options: { low_priority: true })
    response = request.perform

    assert_equal :ok, response.meaning
    assert_equal 200, response.code
    assert_equal({ "StatusCode" => 200, "Value" => 0.025075, "Threshold" => 1, "Message" => "" }, response.body)
  end
end
