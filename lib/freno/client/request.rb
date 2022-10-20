# frozen_string_literal: true

require_relative "preconditions"
require_relative "result"
require_relative "errors"

module Freno
  class Client
    class Request
      include Freno::Client::Preconditions

      attr_reader :faraday, :args, :options, :raise_on_timeout

      def self.perform(**kwargs)
        new(**kwargs).perform
      end

      def initialize(**kwargs)
        @args    = kwargs
        @faraday = kwargs.delete(:faraday) || nil
        @options = kwargs.delete(:options) || {}

        @raise_on_timeout = options.fetch(:raise_on_timeout, true)
        @verb = options.fetch(:verb, :head)
      end

      def perform
        response = request(verb, path, params)
        process_response(response)
      rescue Faraday::TimeoutError => error
        raise Freno::Error, error if raise_on_timeout

        Result.from_meaning(:request_timeout)
      rescue StandardError => error
        raise Freno::Error, error
      end

      protected

      def request(verb, path, params)
        faraday.send(verb, path, params)
      end

      def path
        @path || begin
          raise NotImplementedError("must be overriden in specific requests, or memoized in @path")
        end
      end

      def verb
        @verb || begin
          raise NotImplementedError("must be overriden in specific requests, or memoized in @verb")
        end
      end

      def params
        @params ||= {}
      end

      def process_response(response)
        Result.from_faraday_response(response)
      end
    end
  end
end
