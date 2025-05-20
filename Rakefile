require "bundler/setup"
require "bundler/gem_tasks"
require "standard/rake"

task :format do
  `bundle exec standardrb --fix`
  `bundle exec magic_frozen_string_literal .`
end

task default: %i[test standard]
