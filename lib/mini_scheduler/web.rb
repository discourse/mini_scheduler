# frozen_string_literal: true
# Based off sidetiq https://github.com/tobiassvn/sidetiq/blob/master/lib/sidetiq/web.rb
module MiniScheduler
  module Web
    VIEWS = File.expand_path('views', File.dirname(__FILE__)) unless defined? VIEWS

    def self.find_schedules_by_time
      Manager.discover_schedules.sort do |a, b|
        a_next = a.schedule_info.next_run
        b_next = b.schedule_info.next_run
        if a_next && b_next
          a_next <=> b_next
        elsif a_next
          -1
        else
          1
        end
      end
    end

    def self.registered(app)

      app.helpers do
        def sane_time(time)
          return unless time
          time
        end

        def sane_duration(duration)
          return unless duration
          if duration < 1000
            "#{duration}ms"
          else
            "#{'%.2f' % (duration / 1000.0)} secs"
          end
        end
      end

      app.get "/scheduler" do
        MiniScheduler.before_sidekiq_web_request&.call
        @schedules = Web.find_schedules_by_time
        erb File.read(File.join(VIEWS, 'scheduler.erb')), locals: { view_path: VIEWS }
      end

      app.get "/scheduler/history" do
        MiniScheduler.before_sidekiq_web_request&.call
        @schedules = Manager.discover_schedules
        @schedules.sort_by!(&:to_s)
        @scheduler_stats = Stat.order('started_at desc')

        @filter = params[:filter]
        names = @schedules.map(&:to_s)
        @filter = nil if !names.include?(@filter)
        if @filter
          @scheduler_stats = @scheduler_stats.where(name: @filter)
        end

        @scheduler_stats = @scheduler_stats.limit(200)
        erb File.read(File.join(VIEWS, 'history.erb')), locals: { view_path: VIEWS }
      end

      app.post "/scheduler/:name/trigger" do
        halt 404 unless (name = params[:name])

        MiniScheduler.before_sidekiq_web_request&.call

        klass = name.constantize
        info = klass.schedule_info
        info.next_run = Time.now.to_i
        info.write!

        redirect "#{root_path}scheduler"
      end

    end
  end
end

Sidekiq::Web.register(MiniScheduler::Web)
Sidekiq::Web.tabs["Scheduler"] = "scheduler"
