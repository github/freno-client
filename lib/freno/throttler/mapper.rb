# frozen_string_literal: true

module Freno
  class Throttler
    # A Mapper is any object that responds to `call`, by receiving a context
    # object and returning a list of strings, each of which corresponds to the
    # store_name that will be checked in freno.
    #
    # See https://github.com/github/freno/blob/master/doc/http.md#client-requests
    # for more context.
    #
    # As an example we could use a mapper that will receive as a context a set
    # of [table, shard_id] tuples, and could return the list of all the stores
    # where that shards exist.
    #
    module Mapper
      # The Identity mapper is the one used by default in the Throttler.
      #
      # It works by informing the throttler to check exact same stores that it
      # receives as context, without any translation.
      #
      # Let's use the following throttler, which uses Mapper::Identity
      # implicitly.
      #
      # ```ruby
      # throttler = Throttler.new(client: freno_client, app: :my_app)
      # data.find_in_batches do |batch|
      #   throttler.throttle([:mysqla, :mysqlb]) do
      #     update(batch)
      #   end
      # end
      # ```
      #
      # Before each call to `update(batch)` the throttler will call freno to
      # check the health of `mysqla` and `mysqlb`. And sleep if any of them is
      # not ok.
      #
      class Identity
        def self.call(context)
          Array(context)
        end
      end
    end
  end
end
