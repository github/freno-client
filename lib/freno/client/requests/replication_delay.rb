# frozen_string_literal: true

require_relative "../request"

module Freno
  class Client
    module Requests
      class ReplicationDelay < Check
        protected

        def process_response(*)
          response = super
          response.body["Value"]
        end

        def verb
          :get
        end
      end
    end
  end
end
