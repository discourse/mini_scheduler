# frozen_string_literal: true
# encoding: utf-8

require "sidekiq/web"
require "mini_scheduler/web"

describe MiniScheduler::Web do
  it "registers with Sidekiq::Web" do
    expect(Sidekiq::Web.tabs["Scheduler"]).to eq "scheduler"
  end
end
