# frozen_string_literal: true

require_relative "../request"

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

          # A low priority check is handled slightly differently by Freno. If
          # the p=low GET parameter is passed, the check will fail for any app
          # with failed checks within the last second. This failure is returned
          # quickly, without checking the underlying metric.
          params[:p] = "low" if options[:low_priority]

          @path = "check-read/#{app}/#{store_type}/#{store_name}/#{threshold.to_f.round(3)}"
        end
      end
    end
  end
end
