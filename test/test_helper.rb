# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
require_relative "side_effects_helper"

ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

module JourneyDefinitionHelper
  def create_journey_subclass(&blk)
    # https://stackoverflow.com/questions/4113479/dynamic-class-definition-with-a-class-name
    random_component = Random.hex(2)
    random_name = "JourneySubclass#{random_component}"
    klass = Class.new(StepperMotor::Journey, &blk)
    Object.const_set(random_name, klass)
    klass
  end
end

module Despec
  def it(desc)
    test(desc) do
      flunk "To rewrite: #{desc}"
    end
  end
end

ActiveSupport::TestCase.include(JourneyDefinitionHelper)
ActiveSupport::TestCase.extend(Despec)
