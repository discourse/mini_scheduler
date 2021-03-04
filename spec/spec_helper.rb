# frozen_string_literal: true

require 'mini_scheduler'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'mocha/api'

def wait_for(on_fail: nil, &blk)
  i = 0
  result = false
  while !result && i < 1000
    result = blk.call
    i += 1
    sleep 0.001
  end

  on_fail&.call
  expect(result).to eq(true)
end

class TrackTimeStub
  def self.stubbed
    false
  end
end

def freeze_time(now = Time.now)
  datetime = DateTime.parse(now.to_s)
  time = Time.parse(now.to_s)

  if block_given?
    raise "nested freeze time not supported" if TrackTimeStub.stubbed
  end

  DateTime.stubs(:now).returns(datetime)
  Time.stubs(:now).returns(time)
  Date.stubs(:today).returns(datetime.to_date)
  TrackTimeStub.stubs(:stubbed).returns(true)

  if block_given?
    begin
      yield
    ensure
      unfreeze_time
    end
  end
end

def unfreeze_time
  DateTime.unstub(:now)
  Time.unstub(:now)
  Date.unstub(:today)
  TrackTimeStub.unstub(:stubbed)
end

RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :mocha

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.order = :random

  config.filter_run_when_matching :focus
end
