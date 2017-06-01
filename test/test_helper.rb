$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'faraday'
require 'freno/client'
require 'minitest/autorun'

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
