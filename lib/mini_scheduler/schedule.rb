module MiniScheduler::Schedule

  def daily(options = nil)
    if options
      @daily = options
    end
    @daily
  end

  def every(duration = nil)
    if duration
      @every = duration
      if manager = MiniScheduler::Manager.current
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
    !!@every || !!@daily || !!@async
  end

  # schedule job asynchronously in new thread
  def async(value = nil)
    if value != nil
      @async = value
    end
    @async
  end
end
