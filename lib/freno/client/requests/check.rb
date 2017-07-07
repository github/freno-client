require_relative '../request'

module Freno
  class Client
    module Requests
      class Check < Request

        def initialize(**kwargs)
          super

          app        = kwargs.fetch(:app)
          store_type = kwargs.fetch(:store_type)
          store_name = kwargs.fetch(:store_name)

          check do
            present app: app, store_type: store_type, store_name: store_name
          end

          @path = "check/#{app}/#{store_type}/#{store_name}"
        end
      end
    end
  end
end
