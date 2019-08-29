# frozen_string_literal: true
require "mini_scheduler/engine"
require 'mini_scheduler/schedule'
require 'mini_scheduler/schedule_info'
require 'mini_scheduler/manager'
require 'mini_scheduler/distributed_mutex'
require 'sidekiq/exception_handler'

module MiniScheduler

  def self.configure
    yield self
  end

  class SidekiqExceptionHandler
    extend Sidekiq::ExceptionHandler
  end

  def self.job_exception_handler(&blk)
    @job_exception_handler = blk if blk
    @job_exception_handler
  end

  def self.handle_job_exception(ex, context = {})
    if job_exception_handler
      job_exception_handler.call(ex, context)
    else
      SidekiqExceptionHandler.handle_exception(ex, context)
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

      schedules.each do |schedule|
        if schedule.queue == queue
          manager.ensure_schedule!(schedule)
        end
      end

      Thread.new do
        while true
          begin
            if !self.skip_schedule || !self.skip_schedule.call
              manager.tick
            end
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
