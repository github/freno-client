require_relative '../request'

module Freno
  class Client
    module Requests
      class CheckRead < Request

        def initialize(**args)
          super

          app        = args.fetch(:app)
          store_type = args.fetch(:store_type)
          store_name = args.fetch(:store_name)
          threshold  = args.fetch(:threshold)

          check do
            present app: app, store_type: store_type, store_name: store_name, threshold: threshold
          end

          @path = "check-read/#{app}/#{store_type}/#{store_name}/#{threshold.to_f.round(3)}"
        end
      end
    end
  end
end
