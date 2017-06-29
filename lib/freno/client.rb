require "freno/client/version"
require "freno/client/requests/check_read"
require "freno/client/requests/check"

module Freno
  class Client

    attr_accessor :default_app, :default_store_name, :default_store_type, :options
    attr_reader   :faraday

    def initialize(faraday)
      @faraday = faraday
      @default_store_type = :mysql
      @options = {}
      yield self if block_given?
    end

    def check(app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      Requests::Check.new(faraday, app: app, store_type: store_type, store_name: store_name, options: options).perform
    end

    def check?(app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      check(app: app, store_type: store_type, store_name: store_name, options: options).ok?
    end

    def check_read(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      Requests::CheckRead.new(faraday, app: app, store_type: store_type, store_name: store_name, threshold: threshold, options: options).perform
    end

    def check_read?(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      check_read(threshold: threshold, app: app, store_type: store_type, store_name: store_name, options: options).ok?
    end
  end
end
