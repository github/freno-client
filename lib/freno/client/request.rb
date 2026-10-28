# frozen_string_literal: true

require_relative "preconditions"
require_relative "result"
require_relative "errors"

module Freno
  class Client
    class Request
      include Freno::Client::Preconditions

      # Header marking a request as a retry of a previously failed request, so
      # load balancers can identify retry traffic.
      RETRY_HEADER = "X-Is-Retry"

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

        headers[RETRY_HEADER] = "true" if options[:is_retry]
      end

      def perform
        response = headers.empty? ? request(verb, path, params) : request(verb, path, params, headers)
        process_response(response)
      rescue Faraday::TimeoutError => error
        raise Freno::Error, error if raise_on_timeout

        Result.from_meaning(:request_timeout)
      rescue StandardError => error
        raise Freno::Error, error
      end

      protected

      def request(verb, path, params, headers = nil)
        faraday.send(verb, path, params, headers)
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

      def headers
        @headers ||= {}
      end

      def process_response(response)
        Result.from_faraday_response(response)
      end
    end
  end
end
