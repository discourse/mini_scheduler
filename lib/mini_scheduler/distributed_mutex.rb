module MiniScheduler
  class DistributedMutex

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

    # NOTE wrapped in mutex to maintain its semantics
    def synchronize
      @mutex.lock
      while !try_to_get_lock
        sleep 0.001
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
