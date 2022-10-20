# frozen_string_literal: true

require_relative "../request"

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

          # A low priority check is handled slightly differently by Freno. If
          # the p=low GET parameter is passed, the check will fail for any app
          # with failed checks within the last second. This failure is returned
          # quickly, without checking the underlying metric.
          params[:p] = "low" if options[:low_priority]

          @path = "check/#{app}/#{store_type}/#{store_name}"
        end
      end
    end
  end
end
