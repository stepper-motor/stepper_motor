# frozen_string_literal: true

require "test_helper"

class StepDefinitionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "does not allow invalid values for after: and wait:" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 10.hours do
          # pass
        end

        step after: 5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step wait: -5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 5.hours, wait: 2.seconds do
          # pass
        end
      end
    end
  end

  test "forbids multiple steps with the same name within a journey" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step :foo do
          true
        end

        step "foo" do
          true
        end
      end
    end
  end
end
