module Freno
  class Client
    module Requests
      module Preconditions
        extend self

        PreconditionNotMet = Class.new(ArgumentError)

        class Checker
          attr_reader :errors

          def initialize
            @errors = []
          end

          def present(args = {})
            args.each do |arg, value|
              unless value
                errors << "#{arg} should be present"
              end
            end
          end

          def float(args = {})
            args.each do |arg, value|
              unless value.is_a? Float
                errors << "#{arg} should be a float precision number"
              end
            end
          end

          def report
            raise PreconditionNotMet.new(errors.join("\n")) unless errors.empty?
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
end
