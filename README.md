# Freno Client [![Build Status](https://travis-ci.org/github/freno-client.svg)](https://travis-ci.org/github/freno-client)

A ruby client for [Freno](https://github.com/github/freno): the cooperative, highly available throttler service.

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


## Development

After checking out the repo, run `script/bootstrap` to install dependencies. Then, run `script/test` to run the tests. You can also run `script/console` for an interactive prompt that will allow you to experiment.

## Contributing

This repository is open to [contributions](CONTRIBUTING.md). Contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Releasing

If you are the current maintainer of this gem:

1. Create a branch for the release: `git checkout -b cut-release-vx.y.z`
1. Make sure your local dependencies are up to date: `script/bootstrap`
1. Ensure that tests are green: `bundle exec rake test`
1. Bump gem version in `lib/freno/client/version.rb`
1. Merge a PR to github/freno-client containing the changes in the version file
1. Run `script/release`

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
