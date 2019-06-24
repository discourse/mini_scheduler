# frozen_string_literal: true

MiniScheduler.configure do |config|
  # An instance of Redis. See https://github.com/redis/redis-rb

  # config.redis = $redis

  # Define a custom exception handler when an exception is raised
  # by a scheduled job. By default, SidekiqExceptionHandler is used.

  # config.job_exception_handler do |ex, context|
  #   ...
  # end

  # Add code to be called after a scheduled job runs. An argument
  # with stats about the execution is passed, including these fields:
  # name, hostname, pid, started_at, duration_ms, live_slots_start,
  # live_slots_finish, success, error

  # config.job_ran do |stats|
  #   ...
  # end

  # Before each tick, the configured block is run to check if the next job
  # should be scheduled. The block should return a boolean where a return value
  # of `True` skip scheduling.

  # config.skip_schedule do
  #   ...
  # end

  # Add code that runs before processing requests to the
  # scheduler pages of the Sidekiq web UI.

  # config.before_sidekiq_web_request do
  #   ...
  # end
end

if Sidekiq.server? && defined?(Rails)
  Rails.application.config.after_initialize do
    MiniScheduler.start
  end
end
