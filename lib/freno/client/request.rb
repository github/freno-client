require_relative 'preconditions'
require_relative 'result'

module Freno
  class Client
    class Request

      include Freno::Client::Preconditions

      attr_reader :faraday, :args, :options
      attr_reader :raise_on_timeout

      def self.perform(**args)
        new(**args).perform
      end

      def initialize(**args)
        @args    = args
        @faraday = args.delete(:faraday) || nil
        @options = args.delete(:options) || Hash.new

        @raise_on_timeout = options.fetch(:raise_on_timeout, true)
        @verb = options.fetch(:verb, :head)
      end

      def perform
        begin
          response = request(verb, path)
        rescue Faraday::TimeoutError => ex
          raise ex if raise_on_timeout
          Result.from_meaning(:request_timeout)
        else
          process_response(response)
        end
      end

      protected

      def request(verb, path)
        faraday.send(verb, path)
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

      def process_response(response)
        Result.from_faraday_response(response)
      end
    end
  end
end
