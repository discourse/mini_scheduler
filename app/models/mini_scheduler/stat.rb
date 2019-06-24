# frozen_string_literal: true

if defined?(ActiveRecord::Base)
  module MiniScheduler
    class Stat < ActiveRecord::Base

      self.table_name = 'scheduler_stats'

      def self.purge_old
        where('started_at < ?', 1.months.ago).delete_all
      end
    end
  end
end
