# frozen_string_literal: true

module Freno
  class Client
    module Preconditions
      module_function

      PreconditionNotMet = Class.new(ArgumentError)

      class Checker
        attr_reader :errors

        def initialize
          @errors = []
        end

        def present(args = {})
          args.each do |arg, value|
            errors << "#{arg} should be present" unless value
          end
        end

        def report
          raise PreconditionNotMet, errors.join("\n") unless errors.empty?
        end
      end

      def check(&block)
        checker = Checker.new
        checker.instance_eval(&block)
        checker.report
      end
    end
  end
end
