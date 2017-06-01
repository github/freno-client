module Freno
  class Client
    module Requests
      class Result

        # https://github.com/github/freno/blob/master/doc/http.md#status-codes
        FRENO_STATUS_CODE_MEANINGS = {
          200 => :ok,
          404 => :not_found,
          417 => :expectation_failed,
          429 => :too_many_requests,
          500 => :internal_server_error
        }.freeze

        # these are included to add resiliency to freno-client
        ADDITIONAL_STATUS_CODE_MEANINGS = {
          408 => :request_timeout
        }.freeze

        CODE_MEANINGS = FRENO_STATUS_CODE_MEANINGS.merge(ADDITIONAL_STATUS_CODE_MEANINGS).freeze
        MEANING_CODES = CODE_MEANINGS.invert

        def self.from_faraday_response(response)
          from_status_code(response.status)
        end

        def self.from_meaning(meaning)
          from_status_code(MEANING_CODES[meaning] || 0)
        end

        def self.from_status_code(status_code)
          new(status_code)
        end

        attr_reader :code, :meaning

        def initialize(code)
          @code = code
          @meaning = CODE_MEANINGS[code] || :unknown
        end

        def ok?
          meaning == :ok
        end

        def failed?
          !ok?
        end

        def unkown?
          meaning == :unkown
        end

        def ==(other)
          return meaning == other if other.is_a? Symbol
          code == other
        end
      end
    end
  end
end
