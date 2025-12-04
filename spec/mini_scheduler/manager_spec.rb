# frozen_string_literal: true
# encoding: utf-8

describe MiniScheduler::Manager do
  module Testing
    class RandomJob
      extend ::MiniScheduler::Schedule

      def self.runs=(val)
        @runs = val
      end

      def self.runs
        @runs ||= 0
      end

      every 5.minutes

      def perform
        self.class.runs += 1
        sleep 0.001
      end
    end

    class SuperLongJob
      extend ::MiniScheduler::Schedule

      every 10.minutes

      def perform
        sleep 1000
      end
    end

    class SuperLongPerHostJob
      extend ::MiniScheduler::Schedule

      per_host
      every 20.minutes

      def perform
        sleep 1000
      end
    end

    class PerHostJob
      extend ::MiniScheduler::Schedule

      per_host
      every 10.minutes

      def self.runs=(val)
        @runs = val
      end

      def self.runs
        @runs ||= 0
      end

      def perform
        self.class.runs += 1
      end
    end

    class FailingJob
      extend ::MiniScheduler::Schedule

      every 5.minutes

      def perform
        1 / 0
      end
    end
  end

  let(:manager) { MiniScheduler::Manager.new(enable_stats: false) }

  let(:redis) { Redis.new }

  before do
    MiniScheduler.configure { |config| config.redis = redis }

    # expect(ActiveRecord::Base.connection_pool.connections.length).to eq(1)
    @thread_count = Thread.list.count

    @backtraces = {}
    Thread.list.each { |t| @backtraces[t.object_id] = t.backtrace }
  end

  after do
    ObjectSpace
      .each_object(described_class)
      .each do |manager|
        manager.stop!
        manager.remove(Testing::RandomJob)
        manager.remove(Testing::SuperLongJob)
        manager.remove(Testing::PerHostJob)
        manager.remove(Testing::FailingJob)
        manager.remove(Testing::SuperLongPerHostJob)
      end

    # connections that are not in use must be removed
    # otherwise active record gets super confused
    # ActiveRecord::Base.connection_pool.connections.reject { |c| c.in_use? }.each do |c|
    #   ActiveRecord::Base.connection_pool.remove(c)
    # end
    # expect(ActiveRecord::Base.connection_pool.connections.length).to (be <= 1)

    on_thread_mismatch =
      lambda do
        current = Thread.list.map { |t| t.object_id }

        old_threads = @backtraces.keys
        extra = current - old_threads

        missing = old_threads - current

        if missing.length > 0
          STDERR.puts "\nMissing Threads #{missing.length} thread/s"
          missing.each do |id|
            STDERR.puts @backtraces[id]
            STDERR.puts
          end
        end

        if extra.length > 0
          Thread.list.each do |thread|
            if extra.include?(thread.object_id)
              STDERR.puts "\nExtra Thread Backtrace:"
              STDERR.puts thread.backtrace
              STDERR.puts
            end
          end
        end
      end

    wait_for(on_fail: on_thread_mismatch) { @thread_count == Thread.list.count }

    redis.flushdb
  end

  it "can disable stats" do
    manager = MiniScheduler::Manager.new(enable_stats: false)
    expect(manager.enable_stats).to eq(false)

    manager.stop!

    manager = MiniScheduler::Manager.new
    expect(manager.enable_stats).to eq(false)
    manager.stop!
  end

  describe "per host jobs" do
    it "correctly schedules on multiple hosts" do
      freeze_time

      Testing::PerHostJob.runs = 0

      hosts = %w[a b c]

      hosts
        .map do |host|
          manager = MiniScheduler::Manager.new(hostname: host, enable_stats: false)
          manager.ensure_schedule!(Testing::PerHostJob)

          info = manager.schedule_info(Testing::PerHostJob)
          info.next_run = Time.now.to_i - 10
          info.write!

          manager
        end
        .each do |manager|
          manager.blocking_tick
          manager.stop!
        end

      expect(Testing::PerHostJob.runs).to eq(3)
    end
  end

  describe "#sync" do
    it "increases" do
      expect(MiniScheduler::Manager.seq).to eq(MiniScheduler::Manager.seq - 1)
    end
  end

  describe "#tick" do
    it "should nuke missing jobs" do
      redis.zadd MiniScheduler::Manager.queue_key("default"), Time.now.to_i - 1000, "BLABLA"
      manager.tick
      expect(redis.zcard(MiniScheduler::Manager.queue_key("default"))).to eq(0)
    end

    context "when manager is stopped" do
      let(:manager) do
        # no workers to ensure the original job doesn't start
        MiniScheduler::Manager.new(enable_stats: false, workers: 0)
      end

      it "can later reschedule jobs" do
        info = manager.schedule_info(Testing::SuperLongJob)
        original_time = Time.now.to_i - 1
        info.next_run = original_time
        info.write!

        manager.tick
        manager.stop!

        redis.del manager.identity_key

        manager = MiniScheduler::Manager.new(enable_stats: false, workers: 0)
        manager.reschedule_orphans!

        info = manager.schedule_info(Testing::SuperLongJob)
        expect(info.next_run).to be <= Time.now.to_i
        expect(info.next_run).to_not eq(original_time)

        manager.stop!
      end
    end

    it "should recover from redis readonly within same manager instance" do
      info = manager.schedule_info(Testing::SuperLongJob)
      info.next_run = Time.now.to_i - 1
      info.write!

      manager.tick

      wait_for { manager.schedule_info(Testing::SuperLongJob).prev_result == "RUNNING" }

      # Simulate redis failure while job is running
      MiniScheduler::ScheduleInfo.any_instance.stubs(:write!).raises(Redis::CommandError)

      runner = manager.instance_variable_get(:@runner)
      worker_threads = runner.instance_variable_get(:@threads)
      worker_thread_ids = runner.worker_thread_ids

      # Now that Redis is broken, simulate the 'SuperLongJob' ending
      worker_threads.each(&:wakeup)

      # Wait until the worker dies due to the redis failure
      wait_for(timeout: 5) { worker_threads.reject(&:alive?).count == 1 }

      # Observe that the status in Redis is stuck on "running"
      expect(manager.schedule_info(Testing::SuperLongJob).prev_result).to eq("RUNNING")

      # Redis back online
      MiniScheduler::ScheduleInfo.any_instance.unstub(:write!)

      # Reschedule should not do anything straight away
      manager.reschedule_orphans!
      expect(manager.schedule_info(Testing::SuperLongJob).prev_result).to eq("RUNNING")

      # Simulate time passing and redis keys expiring
      worker_thread_ids.each do |id|
        expect(manager.redis.ttl(id)).to be > 30
        manager.redis.del(id)
      end

      manager.reschedule_orphans!

      info = manager.schedule_info(Testing::SuperLongJob)
      expect(info.prev_result).to eq("ORPHAN")
      expect(info.next_run).to be <= Time.now.to_i

      runner.instance_variable_get(:@recovery_thread).wakeup
      manager.tick

      wait_for { manager.schedule_info(Testing::SuperLongJob).prev_result == "RUNNING" }
    end

    def queued_jobs(manager, with_hostname:)
      hostname = with_hostname ? manager.hostname : nil
      key = MiniScheduler::Manager.queue_key(manager.queue, hostname)
      redis.zrange(key, 0, -1).map(&:constantize)
    end

    it "should recover from Redis flush" do
      manager = MiniScheduler::Manager.new(enable_stats: false)
      manager.ensure_schedule!(Testing::SuperLongJob)
      manager.ensure_schedule!(Testing::PerHostJob)

      expect(queued_jobs(manager, with_hostname: false)).to include(Testing::SuperLongJob)
      expect(queued_jobs(manager, with_hostname: true)).to include(Testing::PerHostJob)

      redis.scan_each(match: "_scheduler_*") { |key| redis.del(key) }

      expect(queued_jobs(manager, with_hostname: false)).to be_empty
      expect(queued_jobs(manager, with_hostname: true)).to be_empty

      manager.repair_queue

      expect(queued_jobs(manager, with_hostname: false)).to include(Testing::SuperLongJob)
      expect(queued_jobs(manager, with_hostname: true)).to include(Testing::PerHostJob)

      manager.stop!
    end

    it "should only run pending job once" do
      Testing::RandomJob.runs = 0

      info = manager.schedule_info(Testing::RandomJob)
      info.next_run = Time.now.to_i - 1
      info.write!

      (0..5)
        .map do
          Thread.new do
            manager = MiniScheduler::Manager.new(enable_stats: false)
            manager.blocking_tick
            manager.stop!
          end
        end
        .map(&:join)

      expect(Testing::RandomJob.runs).to eq(1)

      info = manager.schedule_info(Testing::RandomJob)
      expect(info.prev_run).to be <= Time.now.to_i
      expect(info.prev_duration).to be > 0
      expect(info.prev_result).to eq("OK")
    end
  end

  describe "#discover_schedules" do
    it "Discovers Testing::RandomJob" do
      expect(MiniScheduler::Manager.discover_schedules).to include(Testing::RandomJob)
    end
  end

  describe ".discover_running_scheduled_jobs" do
    let(:manager_1) { MiniScheduler::Manager.new(enable_stats: false) }
    let(:manager_2) { MiniScheduler::Manager.new(enable_stats: false) }

    before do
      freeze_time

      info = manager_1.schedule_info(Testing::SuperLongJob)
      info.next_run = Time.now.to_i - 1
      info.write!

      manager_1.tick

      info = manager_2.schedule_info(Testing::SuperLongPerHostJob)
      info.next_run = Time.now.to_i - 1
      info.write!

      manager_2.tick

      wait_for do
        manager_1.schedule_info(Testing::SuperLongJob).prev_result == "RUNNING" &&
          manager_2.schedule_info(Testing::SuperLongPerHostJob).prev_result == "RUNNING"
      end
    end

    after do
      manager_1.stop!
      manager_2.stop!
    end

    it "returns running jobs on current host" do
      jobs = described_class.discover_running_scheduled_jobs

      expect(jobs.size).to eq(2)

      super_long_job = jobs.find { |job| job[:class] == Testing::SuperLongJob }

      expect(super_long_job.keys).to eq(%i[class started_at thread_id])
      expect(super_long_job[:started_at]).to be_within(1).of(Time.now)
      expect(super_long_job[:thread_id]).to start_with("_scheduler_#{manager.hostname}")

      expect(
        Thread.list.find do |thread|
          thread[:mini_scheduler_worker_thread_id] == super_long_job[:thread_id]
        end,
      ).to be_truthy

      super_long_per_host_job = jobs.find { |job| job[:class] == Testing::SuperLongPerHostJob }

      expect(super_long_per_host_job.keys).to eq(%i[class started_at thread_id])
      expect(super_long_per_host_job[:started_at]).to be_within(1).of(Time.now)
      expect(super_long_per_host_job[:thread_id]).to start_with("_scheduler_#{manager.hostname}")

      expect(
        Thread.list.find do |thread|
          thread[:mini_scheduler_worker_thread_id] == super_long_per_host_job[:thread_id]
        end,
      ).to be_truthy
    end
  end

  describe "#next_run" do
    it "should be within the next 5 mins if it never ran" do
      manager.remove(Testing::RandomJob)
      manager.ensure_schedule!(Testing::RandomJob)

      expect(manager.next_run(Testing::RandomJob).to_i).to be_within(5.minutes.to_i).of(
        Time.now.to_i + 5.minutes,
      )
    end
  end

  describe "#handle_job_exception" do
    before do
      info = manager.schedule_info(Testing::FailingJob)
      info.next_run = Time.now.to_i - 1
      info.write!
    end

    def expect_job_failure(ex, ctx)
      expect(ex).to be_kind_of ZeroDivisionError
      expect(ctx).to match a_hash_including(
              message: "Error while running a scheduled job",
              job: {
                "class" => Testing::FailingJob,
              },
            )
    end

    context "with default handler" do
      class TempSidekiqLogger
        attr_accessor :exception, :context

        def call(ex, ctx, _config = nil)
          self.exception = ex
          self.context = ctx
        end
      end

      let(:logger) { TempSidekiqLogger.new }

      let(:error_handlers) do
        if defined?(Sidekiq.default_configuration)
          Sidekiq.default_configuration.error_handlers
        else
          Sidekiq.error_handlers
        end
      end

      before { error_handlers << logger }

      after { error_handlers.delete(logger) }

      it "captures failed jobs" do
        manager.blocking_tick

        expect_job_failure(logger.exception, logger.context)
      end
    end

    context "with custom handler" do
      before do
        MiniScheduler.job_exception_handler { |ex, ctx, _config = nil| expect_job_failure(ex, ctx) }
      end

      after { MiniScheduler.instance_variable_set :@job_exception_handler, nil }

      it "captures failed jobs" do
        manager.blocking_tick
      end
    end
  end

  describe "#keep_alive" do
    it "does not raise an error when `skip_runner` is true" do
      manager = MiniScheduler::Manager.new(enable_stats: false, skip_runner: true)
      expect { manager.keep_alive }.not_to raise_error
    end
  end
end
