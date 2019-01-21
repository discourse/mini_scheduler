# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "mini_scheduler/version"

Gem::Specification.new do |spec|
  spec.name          = "mini_scheduler"
  spec.version       = MiniScheduler::VERSION
  spec.authors       = ["Sam Saffron", "Neil Lalonde"]
  spec.email         = ["neil.lalonde@discourse.org"]

  spec.summary       = %q{Adds recurring jobs for Sidekiq}
  spec.description   = %q{Adds recurring jobs for Sidekiq}
  spec.homepage      = "https://github.com/discourse/mini_scheduler"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq"

  spec.add_development_dependency "pg", ">= 1.0"
  spec.add_development_dependency "activesupport", ">= 5.2"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "mock_redis"
end
