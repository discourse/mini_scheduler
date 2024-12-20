# frozen_string_literal: true
require "mini_scheduler/engine"
require "mini_scheduler/schedule"
require "mini_scheduler/schedule_info"
require "mini_scheduler/manager"
require "mini_scheduler/distributed_mutex"
require "sidekiq"
require "redis"

begin
  require "sidekiq/exception_handler"
rescue LoadError
end

module MiniScheduler
  def self.configure
    yield self
  end

  SidekiqExceptionHandler =
    if defined?(Sidekiq.default_configuration) # Sidekiq 7+
      ->(ex, ctx, _config = nil) { Sidekiq.default_configuration.handle_exception(ex, ctx) }
    else # Sidekiq 6.5
      ->(ex, ctx, _config = nil) { Sidekiq.handle_exception(ex, ctx) }
    end

  def self.job_exception_handler(&blk)
    @job_exception_handler = blk if blk
    @job_exception_handler
  end

  def self.handle_job_exception(ex, context = {}, _config = nil)
    if job_exception_handler
      job_exception_handler.call(ex, context)
    else
      SidekiqExceptionHandler.call(ex, context)
    end
  end

  def self.redis=(r)
    @redis = r
  end

  def self.redis
    @redis
  end

  def self.job_ran(&blk)
    @job_ran = blk if blk
    @job_ran
  end

  def self.before_sidekiq_web_request(&blk)
    @before_sidekiq_web_request = blk if blk
    @before_sidekiq_web_request
  end

  def self.skip_schedule(&blk)
    @skip_schedule = blk if blk
    @skip_schedule
  end

  def self.start(workers: 1)
    schedules = Manager.discover_schedules

    Manager.discover_queues.each do |queue|
      manager = Manager.new(queue: queue, workers: workers)

      schedules.each { |schedule| manager.ensure_schedule!(schedule) if schedule.queue == queue }

      Thread.new do
        while true
          begin
            manager.tick if !self.skip_schedule || !self.skip_schedule.call
          rescue => e
            # the show must go on
            handle_job_exception(e, message: "While ticking scheduling manager")
          end

          sleep 1
        end
      end
    end
  end
end
