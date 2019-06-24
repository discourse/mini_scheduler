# frozen_string_literal: true

module MiniScheduler::Schedule

  def queue(value = nil)
    @queue = value.to_s if value
    @queue ||= "default"
  end

  def daily(options = nil)
    if options
      @daily = options
    end
    @daily
  end

  def every(duration = nil)
    if duration
      @every = duration
      if manager = MiniScheduler::Manager.current[queue]
        manager.ensure_schedule!(self)
      end
    end
    @every
  end

  # schedule job independently on each host (looking at hostname)
  def per_host
    @per_host = true
  end

  def is_per_host
    @per_host
  end

  def schedule_info
    manager = MiniScheduler::Manager.without_runner
    manager.schedule_info self
  end

  def scheduled?
    !!@every || !!@daily
  end
end
