# frozen_string_literal: true

require "test_helper"

class UniquenessTest < ActiveSupport::TestCase
  test "forbids multiple similar journeys for the same hero at the same time unless allow_multiple is set" do
    actor_class = create_journey_subclass
    hero = actor_class.create!

    exclusive_journey_class = create_journey_subclass do
      step do
        raise "The step should never be entered as we are not testing the step itself here"
      end
    end

    assert_nothing_raised do
      2.times { exclusive_journey_class.create! }
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      2.times { exclusive_journey_class.create!(hero: hero) }
    end

    assert_nothing_raised do
      2.times { exclusive_journey_class.create!(hero: hero, allow_multiple: true) }
    end
  end

  test "forbids multiple similar journeys for the same hero even if one of them is paused" do
    actor_class = create_journey_subclass
    hero = actor_class.create!

    exclusive_journey_class = create_journey_subclass do
      step do
        raise "The step should never be entered as we are not testing the step itself here"
      end
    end

    ready_journey = exclusive_journey_class.create!(hero:)
    assert ready_journey.ready?
    ready_journey.pause!
    assert ready_journey.paused?

    assert_raises(ActiveRecord::RecordNotUnique) {
      exclusive_journey_class.create!(hero:)
    }
  end
end
