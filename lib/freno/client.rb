require "freno/client/version"
require "freno/client/requests/check_read"

module Freno
  class Client

    attr_accessor :default_app, :default_store_name, :default_store_type
    attr_reader   :faraday

    def initialize(faraday)
      @faraday = faraday
      @default_store_type = :mysql
      yield self if block_given?
    end

    def check_read(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name)
      Requests::CheckRead.new(faraday, app: app, store_type: store_type, store_name: store_name, threshold: threshold).perform
    end

    def check_read?(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name)
      check_read(threshold: threshold, app: app, store_type: store_type, store_name: store_name).ok?
    end
  end
end
