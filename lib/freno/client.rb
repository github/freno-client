require "freno/client/version"
require "freno/client/requests/check_read"
require "freno/client/requests/check"
require "freno/client/requests/replication_delay"

module Freno
  class Client

    REQUESTS = {
      check:             Requests::Check,
      check_read:        Requests::CheckRead,
      replication_delay: Requests::ReplicationDelay,
    }

    attr_reader   :faraday, :decorators, :decorated_requests
    attr_accessor :default_app, :default_store_name, :default_store_type, :options

    def initialize(faraday)
      @faraday            = faraday
      @default_store_type = :mysql
      @options            = {}
      @decorators         = {}
      @decorated_requests = {}

      yield self if block_given?
    end

    def check(app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      perform :check, app: app, store_type: store_type, store_name: store_name, options: options
    end

    def check_read(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      perform :check_read, app: app, store_type: store_type, store_name: store_name, threshold: threshold, options: options
    end

    def replication_delay(app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      perform :replication_delay, app: app, store_type: store_type, store_name: store_name, options: options
    end

    def check?(app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      check(app: app, store_type: store_type, store_name: store_name, options: options).ok?
    end

    def check_read?(threshold:, app: default_app, store_type: default_store_type, store_name: default_store_name, options: self.options)
      check_read(threshold: threshold, app: app, store_type: store_type, store_name: store_name, options: options).ok?
    end

    def decorate(request, with:)
      if request == :all
        requests = REQUESTS.keys
      else
        requests = Array(request)
      end

      requests.each do |request|
        decorators[request] ||= []
        decorators[request] += Array(with)
        decorated_requests[request] = nil
      end
    end

    private

    def perform(request, **kwargs)
      decorated(request).perform(kwargs.merge(faraday: faraday))
    end

    def decorated(request)
      decorated_requests[request] ||= begin
        request_class = REQUESTS[request]
        request_decorators = Array(decorators[request])

        decorated_request = nil
        cursor = nil

        (request_decorators + Array(request_class)).each do |klass|
          if cursor
            cursor.request = klass
            cursor = cursor.request
          else
            decorated_request = klass
            cursor = decorated_request
          end
        end

        decorated_request
      end
    end
  end
end
