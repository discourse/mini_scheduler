# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) if !$LOAD_PATH.include?(lib)
require "mini_scheduler/version"

Gem::Specification.new do |spec|
  spec.name = "mini_scheduler"
  spec.version = MiniScheduler::VERSION
  spec.authors = ["Sam Saffron", "Neil Lalonde"]
  spec.email = ["neil.lalonde@discourse.org"]

  spec.summary = "Adds recurring jobs for Sidekiq"
  spec.description = "Adds recurring jobs for Sidekiq"
  spec.homepage = "https://github.com/discourse/mini_scheduler"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.files = `git ls-files`.split($/).reject { |s| s =~ /^(spec|\.)/ }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "sidekiq", ">= 6.5", "< 8.0"

  spec.add_development_dependency "pg", "~> 1.0"
  spec.add_development_dependency "activesupport", "~> 7.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "mocha", "~> 2.0"
  spec.add_development_dependency "guard", "~> 2.0"
  spec.add_development_dependency "guard-rspec", "~> 4.0"
  spec.add_development_dependency "redis", ">= 4.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop-discourse", "= 3.8.1"
  spec.add_development_dependency "syntax_tree"
end
