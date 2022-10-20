# frozen_string_literal: true

module Freno
  class Throttler
    # A CircuitBreaker is the entry point of the pattern with same name.
    # (see https://martinfowler.com/bliki/CircuitBreaker.html)
    #
    # Clients that use circuit breakers to add resiliency to their processes
    # send `failure` or `sucess` messages to the CircuitBreaker depending on the
    # results of the last requests made.
    #
    # With that information, the circuit breaker determines whether or not to
    # allow the next request (`allow_request?`). A circuit is said to be open
    # when the next request is not allowed; and it's said to be closed when the
    # next request is allowed.
    #
    module CircuitBreaker
      # The Noop circuit breaker is the `:circuit_breaker` used by default in
      # the Throttler
      #
      # It always allows requests, and does nothing when given `success` or
      # `failure` messages. For that reason it doesn't provide any resiliency
      # guarantee.
      #
      # See https://github.com/jnunemaker/resilient for a real ruby implementation
      # of the CircuitBreaker pattern.
      #
      class Noop
        def self.allow_request?
          true
        end

        def self.success; end

        def self.failure; end
      end
    end
  end
end
