[![Build Status](https://github.com/discourse/mini_scheduler/workflows/CI/badge.svg)](https://github.com/discourse/mini_scheduler/actions)
[![Gem Version](https://badge.fury.io/rb/mini_scheduler.svg)](https://rubygems.org/gems/mini_scheduler)

# mini_scheduler

MiniScheduler adds recurring jobs to [Sidekiq](https://sidekiq.org/).



## Installation

Add this line to your application's Gemfile:

```ruby
gem 'mini_scheduler'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install mini_scheduler

In a Rails application, create files needed in your application to configure mini_scheduler:

    bin/rails g mini_scheduler:install
    rake db:migrate

An initializer is created named `config/initializers/mini_scheduler.rb` which lists all the configuration options.

## Configuring MiniScheduler

By default each instance of MiniScheduler will run with a single worker. To amend this behavior:

```
if Sidekiq.server? && defined?(Rails)
  Rails.application.config.after_initialize do
    MiniScheduler.start(workers: 5)
  end
end
```

This is useful for cases where you have extremely long running tasks that you would prefer did not starve.

## Usage

Create jobs with a recurring schedule like this:

```ruby
class MyHourlyJob
  include Sidekiq::Worker
  extend MiniScheduler::Schedule

  every 1.hour

  def execute(args)
    # some tasks
  end
end
```

Options for schedules:

* **queue** followed by a queue name, like "queue :email", default queue is "default"
* **every** followed by a duration in seconds, like "every 1.hour".
* **daily at:** followed by a duration since midnight, like "daily at: 12.hours", to run only once per day at a specific time.

To view the scheduled jobs, their history, and the schedule, go to sidekiq's web UI and look for the "Scheduler" tab at the top.

## How to reach us

If you have questions about using mini_scheduler or found a problem, you can find us at https://meta.discourse.org.
