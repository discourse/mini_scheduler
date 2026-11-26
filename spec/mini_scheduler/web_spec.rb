# frozen_string_literal: true
# encoding: utf-8

require "rack/mock"
require "sidekiq/web"
require "mini_scheduler/web"

describe MiniScheduler::Web do
  module Testing
    class WebJob
      extend ::MiniScheduler::Schedule

      every 1.hour
    end
  end

  # Sidekiq < 8.1 checks a session CSRF token, Sidekiq 8.1+ checks Sec-Fetch-Site.
  def request(method, path, params = {})
    token = SecureRandom.base64(32)
    env =
      Rack::MockRequest.env_for(
        path,
        :method => method,
        :params => params.merge(authenticity_token: token),
        "rack.session" => {
          csrf: token,
        },
        "HTTP_SEC_FETCH_SITE" => "same-origin",
      )
    Sidekiq::Web.call(env)
  end

  it "registers with Sidekiq::Web" do
    expect(Sidekiq::Web.tabs["Scheduler"]).to eq "scheduler"
  end

  describe "POST /scheduler/:name/trigger" do
    it "schedules the job to run now" do
      freeze_time
      info = mock
      info.expects(:next_run=).with(Time.now.to_i)
      info.expects(:write!)
      Testing::WebJob.stubs(:schedule_info).returns(info)

      status, _headers, _body = request("POST", "/scheduler/Testing::WebJob/trigger")
      expect(status).to eq 302
    end
  end

  describe "GET /scheduler/history" do
    # Stat only exists with ActiveRecord, which specs don't load. Define a stand-in
    # and remove it afterwards, so Manager specs don't see stats enabled.
    before do
      MiniScheduler::Manager.stubs(:discover_schedules).returns([Testing::WebJob])
      MiniScheduler.const_set(:Stat, Class.new)
    end

    after { MiniScheduler.send(:remove_const, :Stat) }

    it "filters by schedule name" do
      stats = mock
      stats.expects(:where).with(name: "Testing::WebJob").returns(stats)
      stats.stubs(:limit).returns([])
      MiniScheduler::Stat.stubs(:order).returns(stats)

      status, _headers, _body = request("GET", "/scheduler/history", filter: "Testing::WebJob")
      expect(status).to eq 200
    end
  end
end
