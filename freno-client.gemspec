require_relative "lib/freno/client/version"

Gem::Specification.new do |spec|
  spec.name    = "freno-client"
  spec.version = Freno::Client::VERSION
  spec.author  = "GitHub"
  spec.email   = "opensource+freno-client@github.com"

  spec.summary     = "A library for interacting with Freno, the throttler service"
  spec.description = <<~DESC.gsub(/\s+/, " ")
    freno-client is a Ruby library that interacts with Freno using HTTP.
    Freno is a throttling service and its source code is available at
    https://github.com/github/freno
    DESC

  spec.homepage = "https://github.com/github/freno-client"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 2.5.0"

  spec.files = `git ls-files -z`.split("\x0").grep_v(/^test/)

  spec.add_development_dependency "faraday"
end
