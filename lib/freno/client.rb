# frozen_string_literal: true

require "freno/client/version"
require "freno/client/requests/check_read"
require "freno/client/requests/check"
require "freno/client/requests/replication_delay"

module Freno
  class Client
    class DecorationError < ArgumentError; end

    REQUESTS = {
      check: Requests::Check,
      check_read: Requests::CheckRead,
      replication_delay: Requests::ReplicationDelay
    }.freeze

    attr_reader   :faraday, :decorators, :decorated_requests
    attr_accessor :default_app, :default_store_name, :default_store_type, :options

    # Creates a new instance of the client, that uses faraday to make http calls.
    #
    # If most of the times you are going to ask Freno about the same app and/or storage name,
    # you can tell the client to use some defaults, and override them as necessary.
    #
    # Examples a ruby client that by default asks Freno for throttling information
    # about `:my_app` accessing `:my_cluster` storage.
    #
    #  ```ruby
    #  freno = Freno::Client.new(faraday) do |client|
    #    client.default_store_name = :my_cluster
    #    client.default_app        = :my_app
    #  end
    #  ```
    #
    # Any options set on the Client are passed through to the initialization of
    # each request:
    #
    #  ```ruby
    #  freno = Freno::Client.new(faraday) do |client|
    #    client.options = { raise_on_timeout: false }
    #  end
    #  ```
    #
    #  These default options can be overridden per request. The given options
    #  are merged into the defaults. The request below would be performed with
    #  the options: `{ raise_on_timeout: false, low_priority: true }`
    #
    #  ```ruby
    #  freno = Freno::Client.new(faraday) do |client|
    #    client.options = { raise_on_timeout: false }
    #  end
    #
    #  freno.check?(options: { low_priority: true })
    #  ```
    #
    def initialize(faraday)
      @faraday            = faraday
      @default_store_type = :mysql
      @options            = {}
      @decorators         = {}
      @decorated_requests = {}

      yield self if block_given?
    end

    # Provides an interface to Freno"s check request
    #
    # See https://github.com/github/freno/blob/master/doc/http.md#check-request
    #
    # Returns Result
    #
    def check(app: default_app, store_type: default_store_type, store_name: default_store_name, options: {})
      perform :check, app: app, store_type: store_type, store_name: store_name, options: self.options.merge(options)
    end

    # Provides an interface to Freno"s check-read request
    #
    # See https://github.com/github/freno/blob/master/doc/http.md#specialized-requests
    #
    # Returns Result
    #
    def check_read(
      threshold:,
      app: default_app,
      store_type: default_store_type,
      store_name: default_store_name,
      options: {}
    )
      perform(
        :check_read,
        threshold: threshold,
        app: app,
        store_type: store_type,
        store_name: store_name,
        options: self.options.merge(options)
      )
    end

    # Implements a specific check request to retrieve the consolidated replication
    # delay
    #
    # See https://github.com/github/freno/blob/master/doc/http.md#get-method
    #
    # Returns Float indicating the replication delay in seconds as reported by Freno.
    #
    def replication_delay(
      app: default_app,
      store_type: default_store_type,
      store_name: default_store_name,
      options: {}
    )
      perform(
        :replication_delay,
        app: app,
        store_type: store_type,
        store_name: store_name,
        options: self.options.merge(options)
      )
    end

    # Determines whether Freno considers it"s OK to write to masters
    #
    # Returns true or false.
    #
    def check?(app: default_app, store_type: default_store_type, store_name: default_store_name, options: {})
      check(app: app, store_type: store_type, store_name: store_name, options: self.options.merge(options)).ok?
    end

    # Determines whether it"s OK to read from replicas as replication delay is below
    # the given threshold.
    #
    # Returns true or false.
    #
    def check_read?(
      threshold:,
      app: default_app,
      store_type: default_store_type,
      store_name: default_store_name,
      options: {}
    )
      check_read(
        threshold: threshold,
        app: app,
        store_type: store_type,
        store_name: store_name,
        options: self.options.merge(options)
      ).ok?
    end

    # Configures the client to extend the functionality of part or all the API
    # by means of decorators.
    #
    # A decorator is any object that has a `:request` accessor and can forward
    # the execution of `perform` to it.
    #
    # Examples:
    #
    # The following is a decorator implementing a read-trough cache.
    #
    # ```ruby
    # class Cache
    #   attr_accessor :request
    #
    #   def initialize(cache, ttl)
    #     @cache = cache
    #     @ttl = ttl
    #   end
    #
    #   def perform(**kwargs)
    #     @cache.fetch("freno:client:v1:#{args.hash}", ttl: @ttl) do
    #       request.perform(kwargs)
    #     end
    #   end
    # end
    # ```
    #
    # You can use it to decorate a single kind of request to freno:
    #
    # ```ruby
    # freno = Freno::Client.new(faraday) do |client|
    #   client.decorate :replication_delay, with: Cache.new(App.cache, App.config.ttl)
    # end
    # ```
    #
    # Or every kind of request:
    #
    # ```ruby
    # freno = Freno::Client.new(faraday) do |client|
    #   client.decorate :all, with: Cache.new(App.cache, App.config.ttl)
    # end
    # ```
    #
    # Additionally, decorators can be composed in multiple ways. The following client
    # applies logging and instrumentation to all the requests, and it also applies caching,
    # **before** the previous concerns, to `replication_delay` requests.
    #
    # ```ruby
    # freno = Freno::Client.new(faraday) do |client|
    #   client.decorate :replication_delay, with: caching
    #   client.decorate :all, with: [logging, instrumentation]
    # end
    # ```
    #
    def decorate(request_or_all, with:)
      requests =
        if request_or_all == :all
          REQUESTS.keys
        else
          Array(request_or_all)
        end

      with = Array(with)
      validate!(with)

      requests.each do |request|
        decorators[request] ||= []
        decorators[request] += with
        decorated_requests[request] = nil
      end
    end

    private

    def perform(request, **kwargs)
      decorated(request).perform(faraday: faraday, **kwargs)
    end

    def decorated(request)
      decorated_requests[request] ||= begin
        to_decorate = Array(decorators[request]) + Array(REQUESTS[request])

        outermost = to_decorate[0]
        current = outermost

        (to_decorate[1..]).each do |decorator|
          current.request = decorator
          current = current.request
        end

        outermost
      end
    end

    def validate!(decorators)
      decorators.each do |decorator|
        raise DecorationError, "Cannot reuse decorator instance: #{decorator}" if already_registered?(decorator)

        registered_decorators << decorator
      end
    end

    def already_registered?(decorator)
      registered_decorators.include? decorator
    end

    def registered_decorators
      @registered_decorators ||= Set.new
    end
  end
end
