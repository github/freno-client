# frozen_string_literal: true

require "json"

module Freno
  class Client
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
      MEANING_CODES = CODE_MEANINGS.invert.freeze

      def self.from_faraday_response(response)
        new(response.status, response.body)
      end

      def self.from_meaning(meaning)
        new(MEANING_CODES[meaning] || 0)
      end

      attr_reader :code, :meaning, :raw_body

      def initialize(code, body = nil)
        @code = code
        @meaning = CODE_MEANINGS[code] || :unknown
        @raw_body = body
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

      def body
        @body ||= JSON.parse(raw_body) if raw_body
      end

      def ==(other)
        return meaning == other if other.is_a? Symbol

        code == other
      end
    end
  end
end
