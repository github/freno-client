A Ruby client and throttling library for [Freno](https://github.com/github/freno): the cooperative, highly available throttler service.

## Current status

`Freno::Client`, as [Freno](https://github.com/github/freno) itself, is in active development and its API can still change.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "freno-client"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install freno-client

## Usage

`Freno::Client` uses [faraday](https://github.com/lostisland/faraday) to abstract the http client of your choice:

To start using the client, give it a faraday instance pointing to Freno's base URL.

```ruby
require "freno/client"

FRENO_URL = "http://freno.domain.com:8111"
faraday   = Faraday.new(FRENO_URL)
freno     = Freno::Client.new(faraday)

freno.check?(app: :my_app, store_name: :my_cluster)
# => true

freno.replication_delay(app: :my_app, store_name: :my_cluster)
# => 0.125
```

### Providing sensible defaults

If most of the times you are going to ask Freno about the same app and/or storage name, you can tell the client to use some defaults, and override them as necessary.

```ruby
freno = Freno::Client.new(faraday) do |client|
  client.default_store_name = :my_cluster
  client.default_app        = :my_app
end

freno.check?
# => true (Freno thinks that `my_app` can write to `main` storage)

freno.check?(app: :another_app, store_name: :another_storage)
# => false (Freno thinks that `another_app` should not write to `another_storage`)
```

### What can I do with the client?

#### Asking whether an app can write to a certain storage. ([`check` requests](https://github.com/github/freno/blob/master/doc/http.md#check-requests))

If we want to get a deep sense on why freno allowed or not, writing to a certain storage.

```ruby
result = freno.check(app: :my_app, store_name: :my_cluster)
# => #<Freno::Client::Requests::Result ...>

result.ok?
# => false

result.failed?
# => true

result.code
# => 429

result.meaning
# => :too_many_requests
```

Or if we only want to know if we can write:

```ruby
result = freno.check?(app: :my_app, store_name: :my_cluster)
# => true or false (a shortcut for `check.ok?`)
```

#### Asking whether replication delay is below a certain threshold. ([`check-read` requests](https://github.com/github/freno/blob/master/doc/http.md#specialized-requests))

```ruby
result = freno.check_read(threshold: 0.5, app: :my_app, store_name: :my_cluster)
# => #<Freno::Client::Requests::Result ...>

result.ok?
# => true

result.failed?
# => false

result.code
# => 200

result.meaning
# => :ok
```

Or if we only want to know if we can read:

```ruby
freno.check?(threshold: 0.5, app: :my_app, store_name: :my_cluster)
# => true or false (a shortcut for `check_read.ok?`)
```

#### Asking what's the replication delay

Freno's response to [`GET /check`](https://github.com/github/freno/blob/master/doc/http.md#get-method) includes the replication delay value in seconds. The `replication_delay` method in the client returns this information.

```ruby
freno.replication_delay(app: :my_app, store_name: :my_cluster)
# => 0.125
```

#### Cross-cutting concerns with decorators

Decorators can be used augment the client with custom features.

A decorator is anything that has a `:request` accessor and can forward the execution of `perform` to it.

The following is an example of a decorator implementing a read-trough cache.

```ruby
class Cache
  attr_accessor :request

  def initialize(cache, ttl)
    @cache = cache
    @ttl = ttl
  end

  def perform(**kwargs)
    @cache.fetch("freno:client:v1:#{args.hash}", ttl: @ttl) do
      request.perform(kwargs)
    end
  end
end
```

You can use it to decorate a single kind of request to freno:

```ruby
freno = Freno::Client.new(faraday) do |client|
  client.decorate :replication_delay, with: Cache.new(App.cache, App.config.ttl)
end
```

Or every kind of request:

```ruby
freno = Freno::Client.new(faraday) do |client|
  client.decorate :all, with: Cache.new(App.cache, App.config.ttl)
end
```

Additionally, decorators can be composed in multiple ways. The following client
applies logging and instrumentation to all the requests, and it also applies caching, **before** the previous concerns, to `replication_delay` requests.

```ruby
freno = Freno::Client.new(faraday) do |client|
  client.decorate :replication_delay, with: caching
  client.decorate :all, with: [logging, instrumentation]  
end
```

### Throttler objects

Apart from the operations above, freno-client comes with `Freno::Throttler`, a Ruby library for throttling. You can use it in the following way:

```ruby
require "freno/throttler"

client    = Freno::Client.new(faraday)
throttler = Freno::Throttler.new(client: client, app: :my_app)
context   = :my_cluster

bid_data_set.each_slice(SLICE_SIZE) do |slice|
  throttler.throttle(context) do
    update(slice)
  end
end
```

In the above example, `Freno::Throttler#throttle(context, &block)` will check freno to determine whether is OK to proceed with the given block. If so, the block will be executed immediately, otherwise the throttler will sleep and try
again.

#### Throttler configuration

```ruby
module Freno
  class Throttler

    DEFAULT_WAIT_SECONDS = 0.5
    DEFAULT_MAX_WAIT_SECONDS = 10

    def initialize(client: nil,
                    app: nil,
                    mapper: Mapper::Identity,
                    instrumenter: Instrumenter::Noop,
                    circuit_breaker: CircuitBreaker::Noop,
                    wait_seconds: DEFAULT_WAIT_SECONDS,
                    max_wait_seconds: DEFAULT_MAX_WAIT_SECONDS)


      @client           = client
      @app              = app
      @mapper           = mapper
      @instrumenter     = instrumenter
      @circuit_breaker  = circuit_breaker
      @wait_seconds     = wait_seconds
      @max_wait_seconds = max_wait_seconds

      yield self if block_given?

      validate_args
    end

    ...
  end
end
```

A Throttler instance will make calls to freno on behalf of the given `app`,
using the given `client` (an instance of `Freno::Client`).

You optionally provide the time you want the throttler to sleep in case the check to freno fails, this is `wait_seconds`.

If replication lags badly, you can control until when you want to keep sleeping
and retrying the check by setting `max_wait_seconds`. When that times out, the throttle will raise a `Freno::Throttler::WaitedTooLong` error.

#### Instrumenting the throttler

You can also configure the throttler with an `instrumenter` collaborator to subscribe to events happening during the `throttle` call.

An instrumenter is an object that responds to `instrument(event_name, payload = {})` to receive events from the throttler. One could use `ActiveSupport::Notifications` as an instrumenter and subscribe to "freno.*" events somewhere else in the application, or implement one like the following to push some metrics to a stats system.

```ruby
  class StatsInstrumenter

    attr_reader :stats

    def initialize(stats:)
      @stats = stats
    end

    def instrument(event_name, payload)
      method = event_name.sub("throttler.", "")
      send(method, payload) if respond_to?(method)
    end

    def called(payload)
      increment("throttler.called", tags: extract_tags(payload))
    end

    def waited(payload)
      stats.histogram("throttler.waited", payload[:waited], tags: extract_tags(payload))
    end

    ...

    def circuit_open(payload)
      stats.increment("throttler.circuit_open", tags: extract_tags(payload))
    end

    private

    def extract_tags(payload)
      cluster_names = payload[:store_names] || []
      cluster_tags = cluster_names.map{ |cluster_name| "cluster:#{cluster_name}" }
    end
  end
```

#### Adding resiliency

The throttler can also receive a `circuit_breaker` object to implement resiliency.

With that information it receives, the circuit breaker determines whether or not to allow the next request. A circuit is said to be open when the next request is not allowed; and it's said to be closed when the next request is allowed

If the throttler waited too long, or an unexpected error happened; the circuit breaker will receive a `failure`. If in contrast it succeeded, the circuit breaker will receive a `success` message.

Once the circuit is open, the throttler will not try to throttle calls, an instead throw a `Freno::Throttler::CircuitOpen`

The following is a simple per-process circuit breaker implementation:

```ruby
class MemoryCircuitBreaker

  DEFAULT_CIRCUIT_RETRY_INTERVAL = 10

  def initialize(circuit_retry_interval: DEFAULT_CIRCUIT_RETRY_INTERVAL)
    @circuit_closed = true
    @last_failure = nil
    @circuit_retry_interval = circuit_retry_interval
  end

  def allow_request?
    @circuit_closed || (Time.now - @last_failure) > @circuit_retry_interval
  end

  def success
    @circuit_closed = true
  end

  def failure
    @last_failure = Time.now
    @circuit_closed = false
  end
end
```

#### Flexible throttling strategies

The throttler uses a `mapper` to determine, based on the context provided to `#throttle`, the clusters which replication delay needs to be checked.

By default the throttler uses `Mapper::Identity`, which expect the context to be the store name(s) to check:

```ruby
# will check my_cluster's health
throttler.throttle(:my_cluster) { ... }
# will check the health of cluster_a and cluster_b and throttle if any of them is not OK.
throttler.throttle([:cluster_a, :cluster_b]) { ... }
```

You can create your own mapper, which is just an callable object (like a Proc, or any other object that responds to `call(context)`). The following is a mapper that knows how to throttle access to certain tables and shards.


```ruby
class ShardMapper
  def call(context = {})
    context.map do |table, shards|
      DatabaseStructure.cluster_for(table, shards)
    end
  end
end

throttler = Freno::Throttler.new(client: freno, app: :my_app, mapper: ShardMapper.new)

throttler.throttle(:users => [1,2,3], :repositories => 5) do
  perform_writes
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

This repository is open to [contributions](CONTRIBUTING.md). Contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Releasing

If you are the current maintainer of this gem:

1. Create a branch for the release: `git checkout -b cut-release-vx.y.z`
1. Make sure your local dependencies are up to date: `bin/setup`
1. Ensure that tests are green: `bin/test`
1. Bump gem version in `lib/freno/client/version.rb`
1. Merge a PR to github/freno-client containing the changes in the version file
1. Run `bin/release`

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
