module MiniScheduler
  module Deferrable
    def initialize
      @async = !(defined?(Rails) && Rails.env.test?)
      @queue = Queue.new
      @mutex = Mutex.new
      @paused = false
      @thread = nil
    end

    def length
      @queue.length
    end

    def pause
      stop!
      @paused = true
    end

    def resume
      @paused = false
    end

    # for test and sidekiq
    def async=(val)
      @async = val
    end

    def later(desc = nil, label = 'default', &blk)
      if @async
        start_thread unless @thread&.alive? || @paused
        @queue << [label, blk, desc]
      else
        blk.call
      end
    end

    def stop!
      @thread.kill if @thread&.alive?
      @thread = nil
    end

    # test only
    def stopped?
      !@thread&.alive?
    end

    def do_all_work
      while !@queue.empty?
        do_work(_non_block = true)
      end
    end

    private

    def start_thread
      @mutex.synchronize do
        return if @thread&.alive?
        @thread = Thread.new { do_work while true }
      end
    end

    # using non_block to match Ruby #deq
    def do_work(non_block = false)
      label, job, desc = @queue.deq(non_block)

      MiniScheduler.perform_with_label.call(label) do
        begin
          job.call
        rescue => ex
          MiniScheduler.handle_job_exception(ex, message: "Running deferred code '#{desc}'")
        end
      end
    rescue => ex
      MiniScheduler.handle_job_exception(ex, message: "Processing deferred code queue")
    ensure
      if defined?(ActiveRecord::Base)
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end
    end
  end

  class Defer
    extend Deferrable
    initialize
  end
end
