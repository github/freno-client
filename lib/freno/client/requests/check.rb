require_relative '../request'

module Freno
  class Client
    module Requests
      class Check < Request

        def initialize(faraday, **args)
          super(faraday, args)

          app        = args.fetch(:app)
          store_type = args.fetch(:store_type)
          store_name = args.fetch(:store_name)

          check do
            present app: app, store_type: store_type, store_name: store_name
          end

          @path = "check/#{app}/#{store_type}/#{store_name}"
        end
      end
    end
  end
end
