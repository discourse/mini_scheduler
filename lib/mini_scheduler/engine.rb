# frozen_string_literal: true

if defined?(::Rails)
  module MiniScheduler
    class Engine < ::Rails::Engine
      isolate_namespace MiniScheduler
    end
  end
end
