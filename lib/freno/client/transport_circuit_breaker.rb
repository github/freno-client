# frozen_string_literal: true

require "faraday"
require_relative "errors"

module Freno
  class Client
    class TransportCircuitBreaker
      class CircuitOpen < Freno::Error; end

      METHODS = %i[allow_request? success failure].freeze
      CONTEXT_KEY = :freno_transport_circuit_breaker_context

      class RequestMarker < Faraday::Middleware
        def initialize(app, transport_circuit_breaker)
          super(app)
          @transport_circuit_breaker = transport_circuit_breaker
        end

        def call(env)
          @transport_circuit_breaker.bind_request(env)
          @app.call(env)
        end
      end
      private_constant :RequestMarker

      class ResponseObserver < Faraday::Middleware
        def initialize(app, transport_circuit_breaker)
          super(app)
          @transport_circuit_breaker = transport_circuit_breaker
        end

        def call(env)
          context = @transport_circuit_breaker.begin_attempt(env)
          @app.call(env).on_complete do |response_env|
            on_complete(context, response_env)
          end
        end

        def on_complete(context, env)
          @transport_circuit_breaker.observe(context, env.status)
        end
      end
      private_constant :ResponseObserver

      def initialize(circuit_breaker:, faraday:)
        missing_methods = METHODS.reject { |method| circuit_breaker.respond_to?(method) }
        unless missing_methods.empty?
          raise ArgumentError, "circuit breaker must respond to #{missing_methods.join(', ')}"
        end

        @circuit_breaker = circuit_breaker
        @mutex = Mutex.new
        install_middleware(faraday)
      end

      def call
        raise CircuitOpen, "Freno transport circuit is open" unless allow_request?

        contexts = (Thread.current[CONTEXT_KEY] ||= {})
        previous_context = contexts[self]
        context = {
          outcome_claimed: false,
          request_env: nil,
          status: nil,
          status_observed: false
        }
        contexts[self] = context

        begin
          response = yield
          status = context[:status_observed] ? context[:status] : response.status
          claim_outcome(context, status)
          response
        rescue StandardError => error
          status = context[:status_observed] ? context[:status] : status_from_error(error)
          claim_outcome(context, status)
          raise
        ensure
          if previous_context
            contexts[self] = previous_context
          else
            contexts.delete(self)
            Thread.current[CONTEXT_KEY] = nil if contexts.empty?
          end
        end
      end

      def bind_request(env)
        context = Thread.current[CONTEXT_KEY]&.fetch(self, nil)
        context[:request_env] ||= env if context
      end

      def begin_attempt(env)
        context = Thread.current[CONTEXT_KEY]&.fetch(self, nil)
        return unless context
        return unless context.fetch(:request_env).equal?(env)

        context[:status] = nil
        context[:status_observed] = false
        context
      end

      def observe(context, status)
        return unless context

        context[:status] = status
        context[:status_observed] = true
      end

      private

      def claim_outcome(context, status)
        return if context[:outcome_claimed]

        context[:outcome_claimed] = true
        record(failure_status?(status) ? :failure : :success)
      end

      def install_middleware(faraday)
        builder = faraday.builder
        if builder.locked?
          raise ArgumentError, "transport circuit breaker must be enabled before the first Faraday request"
        end

        builder.insert(0, RequestMarker, self)
        handlers = builder.handlers
        index = handlers.length
        last_handler = handlers.last
        index -= 1 if last_handler && last_handler.klass <= Faraday::Adapter

        # Response middleware unwinds in reverse order, so the observer goes
        # immediately inside existing validators and before the adapter.
        builder.insert(index, ResponseObserver, self)
      end

      def allow_request?
        @mutex.synchronize { @circuit_breaker.allow_request? }
      end

      def record(outcome)
        @mutex.synchronize { @circuit_breaker.public_send(outcome) }
      end

      def failure_status?(status)
        !status.is_a?(Integer) ||
          !(100..599).cover?(status) ||
          status == 408 ||
          (500..599).cover?(status)
      end

      def status_from_error(error)
        cause = error

        while cause
          return cause.response_status if cause.respond_to?(:response_status) && cause.response_status

          if cause.respond_to?(:response)
            response = cause.response
            return response[:status] if response.respond_to?(:[]) && response[:status]
          end

          cause = cause.cause
        end

        nil
      end
    end
  end
end
