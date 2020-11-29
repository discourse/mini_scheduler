# frozen_string_literal: true

module MiniScheduler
  class Manager
    attr_accessor :random_ratio, :redis, :enable_stats, :queue, :workers

    class Runner
      def initialize(manager)
        @stopped = false
        @mutex = Mutex.new
        @queue = Queue.new
        @manager = manager
        @hostname = manager.hostname

        @recovery_thread = Thread.new do
          while !@stopped
            sleep 60

            @mutex.synchronize do
              repair_queue
              reschedule_orphans
            end
          end
        end
        @keep_alive_thread = Thread.new do
          while !@stopped
            @mutex.synchronize do
              keep_alive
            end
            sleep (@manager.keep_alive_duration / 2)
          end
        end
        @threads = []
        manager.workers.times do
          @threads << Thread.new do
            while !@stopped
              process_queue
            end
          end
        end
      end

      def keep_alive
        @manager.keep_alive
      rescue => ex
        MiniScheduler.handle_job_exception(ex, message: "Scheduling manager keep-alive")
      end

      def repair_queue
        @manager.repair_queue
      rescue => ex
        MiniScheduler.handle_job_exception(ex, message: "Scheduling manager queue repair")
      end

      def reschedule_orphans
        @manager.reschedule_orphans!
      rescue => ex
        MiniScheduler.handle_job_exception(ex, message: "Scheduling manager orphan rescheduler")
      end

      def hostname
        @hostname
      end

      def process_queue

        klass = @queue.deq
        # hack alert, I need to both deq and set @running atomically.
        @running = true

        return if !klass

        failed = false
        start = Time.now.to_f
        info = @mutex.synchronize { @manager.schedule_info(klass) }
        stat = nil
        error = nil

        begin
          info.prev_result = "RUNNING"
          @mutex.synchronize { info.write! }

          if @manager.enable_stats
            stat = MiniScheduler::Stat.create!(
              name: klass.to_s,
              hostname: hostname,
              pid: Process.pid,
              started_at: Time.now,
              live_slots_start: GC.stat[:heap_live_slots]
            )
          end

          klass.new.perform
        rescue => e
          MiniScheduler.handle_job_exception(e, message: "Running a scheduled job", job: { "class" => klass })

          error = "#{e.class}: #{e.message} #{e.backtrace.join("\n")}"
          failed = true
        end
        duration = ((Time.now.to_f - start) * 1000).to_i
        info.prev_duration = duration
        info.prev_result = failed ? "FAILED" : "OK"
        info.current_owner = nil
        if stat
          stat.update!(
            duration_ms: duration,
            live_slots_finish: GC.stat[:heap_live_slots],
            success: !failed,
            error: error
          )
          MiniScheduler.job_ran&.call(stat)
        end
        attempts(3) do
          @mutex.synchronize { info.write! }
        end
      rescue => ex
        MiniScheduler.handle_job_exception(ex, message: "Processing scheduled job queue")
      ensure
        @running = false
        if defined?(ActiveRecord::Base)
          ActiveRecord::Base.connection_handler.clear_active_connections!
        end
      end

      def stop!
        return if @stopped

        @mutex.synchronize do
          @stopped = true

          @keep_alive_thread.kill
          @recovery_thread.kill

          @keep_alive_thread.join
          @recovery_thread.join

          enq(nil)

          kill_thread = Thread.new do
            sleep 0.5
            @threads.each(&:kill)
          end

          @threads.each(&:join)
          kill_thread.kill
          kill_thread.join
        end
      end

      def enq(klass)
        @queue << klass
      end

      def wait_till_done
        while !@queue.empty? && !(@queue.num_waiting > 0)
          sleep 0.001
        end
        # this is a hack, but is only used for test anyway
        # if tests fail that depend on this we are forced to increase it.
        sleep 0.010
        while @running
          sleep 0.001
        end
      end

      def attempts(n)
        n.times {
          begin
            yield; break
          rescue
            sleep Random.rand
          end
        }
      end

    end

    def self.without_runner
      self.new(skip_runner: true)
    end

    def initialize(options = nil)
      @queue = options && options[:queue] || "default"
      @workers = options && options[:workers] || 1
      @redis = MiniScheduler.redis
      @random_ratio = 0.1
      unless options && options[:skip_runner]
        @runner = Runner.new(self)
        self.class.current[@queue] = self
      end

      @hostname = options && options[:hostname]
      @manager_id = SecureRandom.hex

      if options && options.key?(:enable_stats)
        @enable_stats = options[:enable_stats]
      else
        @enable_stats = !!defined?(MiniScheduler::Stat)
      end
    end

    def self.current
      @current ||= {}
    end

    def hostname
      @hostname ||= begin
                      `hostname`.strip
                    rescue
                      "unknown"
                    end
    end

    def schedule_info(klass)
      MiniScheduler::ScheduleInfo.new(klass, self)
    end

    def next_run(klass)
      schedule_info(klass).next_run
    end

    def ensure_schedule!(klass)
      lock do
        schedule_info(klass).schedule!
      end
    end

    def remove(klass)
      lock do
        schedule_info(klass).del!
      end
    end

    def reschedule_orphans!
      lock do
        reschedule_orphans_on!
        reschedule_orphans_on!(hostname)
      end
    end

    def reschedule_orphans_on!(hostname = nil)
      redis.zrange(Manager.queue_key(queue, hostname), 0, -1).each do |key|
        klass = get_klass(key)
        next unless klass
        info = schedule_info(klass)

        if ['QUEUED', 'RUNNING'].include?(info.prev_result) &&
          (info.current_owner.blank? || !redis.get(info.current_owner))
          info.prev_result = 'ORPHAN'
          info.next_run = Time.now.to_i
          info.write!
        end
      end
    end

    def get_klass(name)
      name.constantize
    rescue NameError
      nil
    end

    def repair_queue
      return if redis.exists?(self.class.queue_key(queue)) ||
        redis.exists?(self.class.queue_key(queue, hostname))

      self.class.discover_schedules
        .select { |schedule| schedule.queue == queue }
        .each { |schedule| ensure_schedule!(schedule) }
    end

    def tick
      lock do
        schedule_next_job
        schedule_next_job(hostname)
      end
    end

    def schedule_next_job(hostname = nil)
      (key, due), _ = redis.zrange Manager.queue_key(queue, hostname), 0, 0, withscores: true
      return unless key

      if due.to_i <= Time.now.to_i
        klass = get_klass(key)
        if !klass || (
          (klass.is_per_host && !hostname) || (hostname && !klass.is_per_host)
        )
          # corrupt key, nuke it (renamed job or something)
          redis.zrem Manager.queue_key(queue, hostname), key
          return
        end

        info = schedule_info(klass)
        info.prev_run = Time.now.to_i
        info.prev_result = "QUEUED"
        info.prev_duration = -1
        info.next_run = nil
        info.current_owner = identity_key
        info.schedule!
        @runner.enq(klass)
      end
    end

    def blocking_tick
      tick
      @runner.wait_till_done
    end

    def stop!
      @runner.stop!
      self.class.current.delete(@queue)
    end

    def keep_alive_duration
      60
    end

    def keep_alive
      redis.setex identity_key, keep_alive_duration, ""
    end

    def lock
      MiniScheduler::DistributedMutex.synchronize(Manager.lock_key(queue), MiniScheduler.redis) do
        yield
      end
    end

    def self.discover_queues
      ObjectSpace.each_object(MiniScheduler::Schedule).map(&:queue).to_set
    end

    def self.discover_schedules
      # hack for developemnt reloader is crazytown
      # multiple classes with same name can be in
      # object space
      unique = Set.new
      schedules = []
      ObjectSpace.each_object(MiniScheduler::Schedule) do |schedule|
        if schedule.scheduled?
          next if unique.include?(schedule.to_s)
          schedules << schedule
          unique << schedule.to_s
        end
      end
      schedules
    end

    @mutex = Mutex.new
    def self.seq
      @mutex.synchronize do
        @i ||= 0
        @i += 1
      end
    end

    def identity_key
      @identity_key ||= "_scheduler_#{hostname}:#{Process.pid}:#{self.class.seq}:#{SecureRandom.hex}"
    end

    def self.lock_key(queue)
      "_scheduler_lock_#{queue}_"
    end

    def self.queue_key(queue, hostname = nil)
      if hostname
        "_scheduler_queue_#{queue}_#{hostname}_"
      else
        "_scheduler_queue_#{queue}_"
      end
    end

    def self.schedule_key(klass, hostname = nil)
      if hostname
        "_scheduler_#{klass}_#{hostname}"
      else
        "_scheduler_#{klass}"
      end
    end
  end
end
