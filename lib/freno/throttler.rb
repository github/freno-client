# frozen_string_literal: true

require "freno/client"
require "freno/throttler/errors"
require "freno/throttler/mapper"
require "freno/throttler/instrumenter"
require "freno/throttler/circuit_breaker"

module Freno
  # Freno::Throttler is the class responsible for throttling writes to a cluster
  # or a set of clusters. Throttling means to slow down the pace at which write
  # operations occur by checking with freno whether all the clusters affected by
  # the operation are in good health before allowing it. If any of the clusters
  # is not in good health, the throttler will wait some time and repeat the
  # process.
  #
  # Examples:
  #
  # Let's use the following throttler, which uses Mapper::Identity implicitly.
  # (see #initialze docs)
  #
  # ```
  # throttler = Throttler.new(client: freno_client, app: :my_app)
  # data.find_in_batches do |batch|
  #   throttler.throttle([:mysqla, :mysqlb]) do
  #     update(batch)
  #   end
  # end
  # ```
  #
  # Before each call to `update(batch)` the throttler will call freno to
  # check the health of the `mysqla` and `mysqlb` stores on behalf of :my_app;
  # and sleep if any of the stores is not ok.
  #
  class Throttler
    DEFAULT_WAIT_SECONDS = 0.5
    DEFAULT_MAX_WAIT_SECONDS = 10
    REQUIRED_ARGS = %i[
      client
      app
      mapper
      instrumenter
      circuit_breaker
      wait_seconds
      max_wait_seconds
    ].freeze

    attr_accessor :client,
                  :app,
                  :mapper,
                  :instrumenter,
                  :circuit_breaker,
                  :wait_seconds,
                  :max_wait_seconds

    # Initializes a new instance of the throttler
    #
    # In order to initialize a Throttler you need the following arguments:
    #
    #  - a `client`: a instance of Freno::Client
    #
    #  - an `app`: a symbol indicating the app-name for which Freno will respond
    #    checks.
    #
    # Also, you can optionally provide the following named arguments:
    #
    #  - `:mapper`: An object that responds to `call(context)` and returns a
    #     `Enumerable` of the store names for which we need to wait for
    #     replication delay. By default this is the `IdentityMapper`, which will
    #     check the stores given as context.
    #
    #     For example, if the `throttler` object used the default mapper:
    #
    #      ```
    #      throttler.throttle(:mysqlc) do
    #         update(batch)
    #      end
    #      ```
    #
    #  - `:instrumenter`: An object that responds to
    #     `instrument(event_name, context = {}, &block)` that can be used to
    #     add cross-cutting concerns like logging or stats to the throttler.
    #
    #     By default, the instrumenter is `Instrumenter::Noop`, which does
    #     nothing but yielding the block it receives.
    #
    #  - `:circuit_breaker`: An object responding to `allow_request?`,
    #     `success`, and `failure?`, compatible with `Resilient::CircuitBreaker`
    #     (see https://github.com/jnunemaker/resilient).
    #
    #     By default, the circuit breaker is `CircuitBreaker::Noop`, which
    #     always allows requests, and does not provide resiliency guarantees.
    #
    #  - `:wait_seconds`: A positive float indicating the number of seconds the
    #     throttler will wait before checking again, in case some of the stores
    #     didn't catch-up the last time they were check.
    #
    #  - `:max_wait_seconds`: A positive float indicating the maxium number of
    #     seconds the throttler will wait in total for replicas to catch-up
    #     before raising a `WaitedTooLong` error.
    #
    def initialize(
      client: nil,
      app: nil,
      mapper: Mapper::Identity,
      instrumenter: Instrumenter::Noop,
      circuit_breaker: CircuitBreaker::Noop,
      wait_seconds: DEFAULT_WAIT_SECONDS,
      max_wait_seconds: DEFAULT_MAX_WAIT_SECONDS
    )
      @client           = client
      @app              = app
      @mapper           = mapper
      @instrumenter     = instrumenter
      @circuit_breaker  = circuit_breaker
      @wait_seconds     = wait_seconds
      @max_wait_seconds = max_wait_seconds

      yield self if block_given?

      validate_args
    end

    # This method receives a context to infer the set of stores that it needs to
    # throttle writes to. It can also receive additional options which are
    # passed to the underlying Check request object:
    #
    # ```
    # throttler = Throttler.new(client: freno_client, app: :my_app)
    # data.find_in_batches do |batch|
    #   throttler.throttle(:mysqla, low_priority: true) do
    #     update(batch)
    #   end
    # end
    # ```
    #
    # With that information it asks freno whether all the stores are ok.
    # In case they are, it executes the given block.
    # Otherwise, it waits `wait_seconds` before trying again.
    #
    # In case the throttler has waited more than `max_wait_seconds`, it raises
    # a `WaitedTooLong` error.
    #
    # In case there's an underlying Freno error, it raises a `ClientError`
    # error.
    #
    # In case the circuit breaker is open, it raises a `CircuitOpen` error.
    #
    # this method is instrumented, the instrumenter will receive the following
    # events:
    #
    # - "throttler.called" each time this method is called
    # - "throttler.succeeded" when the stores were ok, before yielding the block
    # - "throttler.waited" when the stores were not ok, after waiting
    #   `wait_seconds`
    # - "throttler.waited_too_long" when the stores were not ok, but the
    #   thottler already waited at least `max_wait_seconds`, right before
    #   raising `WaitedTooLong`
    # - "throttler.freno_errored" when there was an error with freno, before
    #   raising `ClientError`.
    # - "throttler.circuit_open" when the circuit breaker does not allow the
    #   next request, before raising `CircuitOpen`
    #
    def throttle(context = nil, **options)
      store_names = mapper.call(context)
      instrument(:called, store_names: store_names)
      waited = 0

      while true
        unless circuit_breaker.allow_request?
          instrument(:circuit_open, store_names: store_names, waited: waited)
          raise CircuitOpen
        end

        if all_stores_ok?(store_names, **options)
          instrument(:succeeded, store_names: store_names, waited: waited)
          circuit_breaker.success
          break
        end

        if waited + wait_seconds > max_wait_seconds
          instrument(:waited_too_long, store_names: store_names, waited: waited, max: max_wait_seconds)
          circuit_breaker.failure
          raise WaitedTooLong.new(waited_seconds: waited, max_wait_seconds: max_wait_seconds)
        else
          wait
          waited += wait_seconds
          instrument(:waited, store_names: store_names, waited: waited, max: max_wait_seconds)
        end
      end

      yield
    end

    private

    def validate_args
      errors = []

      REQUIRED_ARGS.each do |argument|
        errors << "#{argument} must be provided" unless send(argument)
      end

      unless max_wait_seconds > wait_seconds
        errors << "max_wait_seconds (#{max_wait_seconds}) has to be greather than wait_seconds (#{wait_seconds})"
      end

      raise ArgumentError, errors.join("\n") if errors.any?
    end

    def all_stores_ok?(store_names, **options)
      store_names.all? do |store_name|
        client.check?(app: app, store_name: store_name, options: options)
      end
    rescue Freno::Error => error
      instrument(:freno_errored, store_names: store_names, error: error)
      circuit_breaker.failure
      raise ClientError, error
    end

    def wait
      sleep wait_seconds
    end

    def instrument(event_name, payload = {}, &block)
      instrumenter.instrument("throttler.#{event_name}", payload, &block)
    end
  end
end
