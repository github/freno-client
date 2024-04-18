# frozen_string_literal: true

require_relative "lib/freno/client/version"

Gem::Specification.new do |spec|
  spec.name = "freno-client"
  spec.version = Freno::Client::VERSION
  spec.summary = "A library for interacting with Freno, the throttler service"
  spec.description = <<~DESC.gsub(/\s+/, " ")
    freno-client is a Ruby library that interacts with Freno using HTTP.
    Freno is a throttling service and its source code is available at
    https://github.com/github/freno
  DESC

  spec.author = "GitHub"
  spec.email = "opensource+freno-client@github.com"
  spec.license = "MIT"
  spec.homepage = "https://github.com/github/freno-client"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "https://github.com/github/freno-client/issues",
    "homepage_uri" => "https://github.com/github/freno-client",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/github/freno-client"
  }

  spec.required_ruby_version = ">= 3.0"
  spec.add_dependency "faraday", "< 3"

  spec.files = Dir.glob(["freno-client.gemspec", "lib/**/*.rb", "LICENSE.txt"])
  spec.extra_rdoc_files = ["README.md"]
end
