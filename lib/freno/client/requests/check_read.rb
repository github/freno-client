require_relative '../request'

module Freno
  class Client
    module Requests
      class CheckRead < Request

        def initialize(**kwargs)
          super

          app        = kwargs.fetch(:app)
          store_type = kwargs.fetch(:store_type)
          store_name = kwargs.fetch(:store_name)
          threshold  = kwargs.fetch(:threshold)

          check do
            present app: app, store_type: store_type, store_name: store_name, threshold: threshold
          end

          @path = "check-read/#{app}/#{store_type}/#{store_name}/#{threshold.to_f.round(3)}"
        end
      end
    end
  end
end
