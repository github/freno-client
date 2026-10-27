# frozen_string_literal: true

require_relative "preconditions"
require_relative "result"
require_relative "errors"
require_relative "transport_circuit_breaker"

module Freno
  class Client
    class Request
      include Freno::Client::Preconditions

      attr_reader :faraday, :args, :options, :raise_on_timeout, :transport_circuit_breaker

      def self.perform(**kwargs)
        new(**kwargs).perform
      end

      def initialize(**kwargs)
        @args    = kwargs
        @faraday = kwargs.delete(:faraday) || nil
        @options = kwargs.delete(:options) || {}
        @transport_circuit_breaker = kwargs.delete(:transport_circuit_breaker)

        @raise_on_timeout = options.fetch(:raise_on_timeout, true)
        @verb = options.fetch(:verb, :head)
      end

      def perform
        response =
          if transport_circuit_breaker
            transport_circuit_breaker.call { request(verb, path, params) }
          else
            request(verb, path, params)
          end
        process_response(response)
      rescue TransportCircuitBreaker::CircuitOpen
        # Fail-open wrappers may intentionally rescue the raised Freno::Error.
        raise if raise_on_timeout

        Result.from_meaning(:request_timeout)
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
