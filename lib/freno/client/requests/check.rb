require_relative '../request'

module Freno
  class Client
    module Requests
      class Check < Request

        attr_reader :app, :store_name, :store_type

        def initialize(faraday, app:, store_type:, store_name:, options: {})
          super(faraday, options)

          check do
            present app: app, store_type: store_type, store_name: store_name
          end

          @app        = app
          @store_type = store_type
          @store_name = store_name
          @path       = "check/#{app}/#{store_type}/#{store_name}"
        end
      end
    end
  end
end
