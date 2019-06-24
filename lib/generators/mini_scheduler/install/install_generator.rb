# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/migration'
require 'active_record'

module MiniScheduler
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path('../templates', __FILE__)
      desc "Generate files for MiniScheduler"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migrations
        migration_template("create_mini_scheduler_stats.rb", "db/migrate/create_mini_scheduler_stats.rb")
      end

      def copy_initializer_file
        copy_file "mini_scheduler_initializer.rb", "config/initializers/mini_scheduler.rb"
      end
    end
  end
end
