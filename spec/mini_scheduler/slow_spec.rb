# frozen_string_literal: true
# encoding: utf-8

if ENV["SLOW"]

  class FastJob
    extend ::MiniScheduler::Schedule
    every 1.second

    def self.runs=(val)
      @runs = val
    end

    def self.runs
      @runs ||= 0
    end

    def perform
      sleep 0.001
      self.class.runs += 1
    end
  end

  class SlowJob
    extend ::MiniScheduler::Schedule
    every 5.second

    def self.runs=(val)
      @runs = val
    end

    def self.runs
      @runs ||= 0
    end

    def perform
      sleep 5
      self.class.runs += 1
    end
  end

  describe MiniScheduler::Manager do

    let(:redis) { Redis.new }

    it "can correctly operate with multiple workers" do
      MiniScheduler.configure do |config|
        config.redis = redis
      end

      manager = MiniScheduler::Manager.new(enable_stats: false, workers: 2)

      sched = manager.schedule_info(FastJob)
      # we jitter start times, this bypasses it
      sched.next_run = Time.now + 0.1
      sched.schedule!

      sched = manager.schedule_info(SlowJob)
      # we jitter start times, this bypasses it
      sched.next_run = Time.now + 0.1
      sched.schedule!

      10.times do
        manager.tick
        sleep 1
      end

      manager.stop!

      expect(FastJob.runs).to be > 5
      expect(SlowJob.runs).to be > 0

    end
  end
end
