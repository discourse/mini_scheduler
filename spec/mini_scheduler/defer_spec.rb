# encoding: utf-8

describe MiniScheduler::Defer do
  class DeferInstance
    include MiniScheduler::Deferrable
  end

  def wait_for(timeout, &blk)
    till = Time.now + (timeout.to_f / 1000)
    while Time.now < till && !blk.call
      sleep 0.001
    end
  end

  before do
    @defer = DeferInstance.new
    @defer.async = true
    MiniScheduler.configure do |config|
      config.redis = MockRedis.new
    end
  end

  after do
    @defer.stop!
  end

  it "can pause and resume" do
    x = 1
    @defer.pause

    @defer.later do
      x = 2
    end

    expect(@defer.length).to eq(1)

    @defer.do_all_work

    expect(x).to eq(2)

    @defer.resume

    @defer.later do
      x = 3
    end

    wait_for(10) do
      x == 3
    end

    expect(x).to eq(3)
  end

  it "recovers from a crash / fork" do
    s = nil
    @defer.stop!
    wait_for(10) do
      @defer.stopped?
    end
    # hack allow thread to die
    sleep 0.005

    @defer.later do
      s = "good"
    end

    wait_for(10) do
      s == "good"
    end

    expect(s).to eq("good")
  end

  it "can queue jobs properly" do
    s = nil

    @defer.later do
      s = "good"
    end

    wait_for(10) do
      s == "good"
    end

    expect(s).to eq("good")
  end

end
