# frozen_string_literal: true

require "test_helper"

class WrapConditionalTest < ActiveSupport::TestCase
  # Validate the skip_if condition
  # if ![true, false, nil].include?(@skip_if_condition) && !@skip_if_condition.is_a?(Symbol) && !@skip_if_condition.respond_to?(:call)
  #   raise ArgumentError, "skip_if: condition must be a boolean, nil, Symbol or a callable object, but was a #{@skip_if_condition.inspect}"
  # end

  test "wraps true without negate" do
    conditional = StepperMotor::Conditional.new(true)
    assert_equal true, conditional.satisfied_by?(nil)
    assert_equal true, conditional.satisfied_by?("something")
  end

  test "wraps true with negate" do
    conditional = StepperMotor::Conditional.new(true, negate: true)
    assert_equal false, conditional.satisfied_by?(nil)
    assert_equal false, conditional.satisfied_by?("something")
  end

  test "wraps false without negate" do
    conditional = StepperMotor::Conditional.new(false)
    assert_equal false, conditional.satisfied_by?(nil)
    assert_equal false, conditional.satisfied_by?("something")
  end

  test "wraps false with negate" do
    conditional = StepperMotor::Conditional.new(false, negate: true)
    assert_equal true, conditional.satisfied_by?(nil)
    assert_equal true, conditional.satisfied_by?("something")
  end

  test "wraps nil without negate" do
    conditional = StepperMotor::Conditional.new(nil)
    assert_equal false, conditional.satisfied_by?(nil)
    assert_equal false, conditional.satisfied_by?("something")
  end

  test "wraps nil with negate" do
    conditional = StepperMotor::Conditional.new(nil, negate: true)
    assert_equal true, conditional.satisfied_by?(nil)
    assert_equal true, conditional.satisfied_by?("something")
  end

  test "wraps multiple without negate" do
    conditional = StepperMotor::Conditional.new([true, true])
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new([true, false])
    assert_equal false, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new([false, false])
    assert_equal false, conditional.satisfied_by?(nil)
  end

  test "wraps multiple with proc" do
    conditional = StepperMotor::Conditional.new([true, -> { true }])
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new([true, -> { false }])
    assert_equal false, conditional.satisfied_by?(nil)
  end

  test "wraps multiple with negate" do
    conditional = StepperMotor::Conditional.new([true, true], negate: true)
    assert_equal false, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new([true, false], negate: true)
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new([false, false], negate: true)
    assert_equal true, conditional.satisfied_by?(nil)
  end

  test "wraps callable without negate" do
    conditional = StepperMotor::Conditional.new(-> { :foo })
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> {})
    assert_equal false, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> { false })
    assert_equal false, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> { true })
    assert_equal true, conditional.satisfied_by?(nil)
  end

  test "wraps callable with negate" do
    conditional = StepperMotor::Conditional.new(-> { :foo }, negate: true)
    assert_equal false, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> {}, negate: true)
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> { false }, negate: true)
    assert_equal true, conditional.satisfied_by?(nil)

    conditional = StepperMotor::Conditional.new(-> { true }, negate: true)
    assert_equal false, conditional.satisfied_by?(nil)
  end

  class Doer
    def should_do?
      true
    end
  end

  class NotDoer
    def should_do?
      false
    end
  end

  test "wraps method without negate" do
    doer = Doer.new

    conditional = StepperMotor::Conditional.new(:should_do?)
    assert_equal true, conditional.satisfied_by?(doer)

    not_doer = NotDoer.new
    assert_equal false, conditional.satisfied_by?(not_doer)
  end

  test "wraps method with negate" do
    doer = Doer.new

    conditional = StepperMotor::Conditional.new(:should_do?, negate: true)
    assert_equal false, conditional.satisfied_by?(doer)

    not_doer = NotDoer.new
    assert_equal true, conditional.satisfied_by?(not_doer)
  end

  test "wraps conditional without negate" do
    inner_conditional = StepperMotor::Conditional.new(true)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional)

    assert_equal true, outer_conditional.satisfied_by?(nil)
    assert_equal true, outer_conditional.satisfied_by?("something")
  end

  test "wraps conditional with negate" do
    inner_conditional = StepperMotor::Conditional.new(true)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional, negate: true)

    assert_equal false, outer_conditional.satisfied_by?(nil)
    assert_equal false, outer_conditional.satisfied_by?("something")
  end

  test "wraps negated conditional without negate" do
    inner_conditional = StepperMotor::Conditional.new(true, negate: true)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional)

    assert_equal false, outer_conditional.satisfied_by?(nil)
    assert_equal false, outer_conditional.satisfied_by?("something")
  end

  test "wraps negated conditional with negate" do
    inner_conditional = StepperMotor::Conditional.new(true, negate: true)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional, negate: true)

    assert_equal true, outer_conditional.satisfied_by?(nil)
    assert_equal true, outer_conditional.satisfied_by?("something")
  end

  test "wraps conditional with method" do
    doer = Doer.new
    inner_conditional = StepperMotor::Conditional.new(:should_do?)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional)

    assert_equal true, outer_conditional.satisfied_by?(doer)

    not_doer = NotDoer.new
    assert_equal false, outer_conditional.satisfied_by?(not_doer)
  end

  test "wraps conditional with method and negate" do
    doer = Doer.new
    inner_conditional = StepperMotor::Conditional.new(:should_do?)
    outer_conditional = StepperMotor::Conditional.new(inner_conditional, negate: true)

    assert_equal false, outer_conditional.satisfied_by?(doer)

    not_doer = NotDoer.new
    assert_equal true, outer_conditional.satisfied_by?(not_doer)
  end
end
