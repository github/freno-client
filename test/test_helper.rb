# frozen_string_literal: true

require "faraday"
require "freno/client"
require "freno/throttler"
require "minitest/autorun"
require "mocha/minitest"

class Freno::Client::Test < Minitest::Test
  def stubbed_faraday(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new do |builder|
      builder.adapter :test, stubs
    end
  end

  def stubbed_client(store_name: :main, store_type: :mysql, app: :github, &block)
    Freno::Client.new(stubbed_faraday(&block)) do |freno|
      freno.default_store_name = store_name
      freno.default_store_type = store_type
      freno.default_app        = app
    end
  end
end

class Freno::Throttler::Test < Minitest::Test
  def sample_client(faraday: nil)
    Freno::Client.new(faraday) do |freno|
      freno.default_store_type = :mysql
    end
  end

  class MemoryInstrumenter
    def initialize
      @events = {}
    end

    def instrument(event, payload = {})
      @events[event] ||= []
      @events[event] <<  payload
      yield payload if block_given?
    end

    def events_for(event)
      @events[event]
    end

    def count(event)
      @events[event] ? @events[event].count : 0
    end
  end

  class SingleFailureAllowedCircuitBreaker
    def initialize
      @failed_once = false
    end

    def allow_request?
      !@failed_once
    end

    def success; end

    def failure
      @failed_once = true
    end
  end
end
