require_relative 'preconditions'
require_relative 'result'

module Freno
  class Client
    module Requests
      class Base

        STATUS_MEANINGS = {}

        include Preconditions

        attr_reader :faraday, :options
        attr_reader :raise_on_timeout

        def initialize(faraday, options = {})
          @faraday = faraday
          @options = options
          @raise_on_timeout = options.fetch(:raise_on_timeout, true)
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
          :head
        end

        def process_response(response)
          Result.from_faraday_response(response)
        end
      end
    end
  end
end
