# frozen_string_literal: true

module Freno
  class Throttler
    # An Instrumenter is an object that responds to
    # `instrument(event_name, payload = {})` to receive events from the
    # throttler.
    #
    # As an example, in a rails app one could use ActiveSupport::Notifications
    # as an instrumenter and subscribe to the "freno.*" events somewhere else in
    # the application.
    #
    module Instrumenter
      # The Noop instrumenter is the `:instrumenter` used by default in the
      # Throttler
      #
      # It does nothing but yielding the control to the block given if it is
      # provided.
      #
      class Noop
        def self.instrument(_event_name, payload = {})
          yield payload if block_given?
        end
      end
    end
  end
end
