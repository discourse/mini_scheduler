# frozen_string_literal: true

module MiniScheduler
  class DistributedMutex
    class Timeout < StandardError; end

    @default_redis = nil

    def self.redis=(redis)
      @default_redis = redis
    end

    def self.synchronize(key, redis = nil, &blk)
      self.new(key, redis || @default_redis).synchronize(&blk)
    end

    def initialize(key, redis)
      raise ArgumentError.new('redis argument is nil') if redis.nil?
      @key = key
      @redis = redis
      @mutex = Mutex.new
    end

    MAX_POLLING_ATTEMPTS ||= 60
    BASE_SLEEP_DURATION ||= 0.001
    MAX_SLEEP_DURATION ||= 1

    # NOTE wrapped in mutex to maintain its semantics
    def synchronize
      @mutex.lock

      attempts = 0
      sleep_duration = BASE_SLEEP_DURATION
      while !try_to_get_lock

        sleep(sleep_duration)

        if sleep_duration < MAX_SLEEP_DURATION
          sleep_duration = [sleep_duration * 2, MAX_SLEEP_DURATION].min
        end

        attempts += 1
        raise Timeout if attempts >= MAX_POLLING_ATTEMPTS
      end

      yield

    ensure
      @redis.del @key
      @mutex.unlock
    end

    private

    def try_to_get_lock
      got_lock = false
      if @redis.setnx @key, Time.now.to_i + 60
        @redis.expire @key, 60
        got_lock = true
      else
        begin
          @redis.watch @key
          time = @redis.get @key
          if time && time.to_i < Time.now.to_i
            got_lock = @redis.multi do
              @redis.set @key, Time.now.to_i + 60
            end
          end
        ensure
          @redis.unwatch
        end
      end

      got_lock
    end

  end

end
