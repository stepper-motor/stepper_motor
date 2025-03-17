# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

task :format do
  `bundle exec standardrb --fix *.rb scripts/*`
  `bundle exec magic_frozen_string_literal .`
end

RSpec::Core::RakeTask.new(:spec)
task default: %i[spec standard]
