require_relative 'base'

module Freno
  class Client
    module Requests
      class CheckRead < Base

        attr_reader :app, :store_name, :store_type, :threshold

        def initialize(faraday, threshold:, app:, store_type:, store_name:, options: {})
          super(faraday, options)

          check do
            present app: app, store_type: store_type, store_name: store_name
          end

          @app        = app
          @store_type = store_type
          @store_name = store_name
          @threshold  = threshold.to_f.round(3)
          @path       = "check-read/#{app}/#{store_type}/#{store_name}/#{threshold}"
        end
      end
    end
  end
end
