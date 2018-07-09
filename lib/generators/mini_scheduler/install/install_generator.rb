require 'rails/generators'
require 'rails/generators/migration'

module MiniScheduler
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path('../templates', __FILE__)
      desc "Add the migrations for MiniScheduler"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migrations
        migration_template("create_mini_scheduler_stats.rb", "db/migrate/create_mini_scheduler_stats.rb")
      end
    end
  end
end
