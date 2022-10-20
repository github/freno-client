# frozen_string_literal: true

require "freno/client"

module Freno
  class Throttler
    # Any throttler-related error.
    class Error < Freno::Error; end

    # Raised if the throttler has waited too long for replication delay
    # to catch up.
    class WaitedTooLong < Error
      def initialize(waited_seconds: DEFAULT_WAIT_SECONDS, max_wait_seconds: DEFAULT_MAX_WAIT_SECONDS)
        super("Waited #{waited_seconds} seconds. Max allowed was #{max_wait_seconds} seconds")
      end
    end

    # Raised if the circuit breaker is open and didn't allow latest request
    class CircuitOpen < Error; end

    # Raised if the freno client errored.
    class ClientError < Error; end
  end
end
