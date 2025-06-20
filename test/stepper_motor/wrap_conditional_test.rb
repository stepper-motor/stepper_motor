# frozen_string_literal: true

require "test_helper"

class WrapConditionalTest < ActiveSupport::TestCase

  # Validate the skip_if condition
  # if ![true, false, nil].include?(@skip_if_condition) && !@skip_if_condition.is_a?(Symbol) && !@skip_if_condition.respond_to?(:call)
  #   raise ArgumentError, "skip_if: condition must be a boolean, nil, Symbol or a callable object, but was a #{@skip_if_condition.inspect}"
  # end
  
  test "wraps true without negate" do
    proc = StepperMotor.wrap_conditional true
    assert_equal true, proc.call
    assert_equal true, proc.call("something")
  end

  test "wraps true with negate" do
    proc = StepperMotor.wrap_conditional true, negate: true
    assert_equal false, proc.call
    assert_equal false, proc.call("something")
  end

  test "wraps false without negate" do
    proc = StepperMotor.wrap_conditional false
    assert_equal false, proc.call
    assert_equal false, proc.call("something")
  end

  test "wraps false with negate" do
    proc = StepperMotor.wrap_conditional false, negate: true
    assert_equal true, proc.call
    assert_equal true, proc.call("something")
  end

  test "wraps nil without negate" do
    proc = StepperMotor.wrap_conditional nil
    assert_equal false, proc.call
    assert_equal false, proc.call("something")
  end

  test "wraps nil with negate" do
    proc = StepperMotor.wrap_conditional nil, negate: true
    assert_equal true, proc.call
    assert_equal true, proc.call("something")
  end

  test "wraps multiple without negate" do
    proc = StepperMotor.wrap_conditional [true, true]
    assert_equal true, proc.call
    
    proc = StepperMotor.wrap_conditional [true, false]
    assert_equal false, proc.call

    proc = StepperMotor.wrap_conditional [false, false]
    assert_equal false, proc.call
  end

  test "wraps multiple with proc" do
    proc = StepperMotor.wrap_conditional [true, -> { true }]
    assert_equal true, proc.call
    
    proc = StepperMotor.wrap_conditional [true, -> { false }]
    assert_equal false, proc.call
  end

  test "wraps multiple with negate" do
    proc = StepperMotor.wrap_conditional [true, true], negate: true
    assert_equal false, proc.call
    
    proc = StepperMotor.wrap_conditional [true, false], negate: true
    assert_equal true, proc.call

    proc = StepperMotor.wrap_conditional [false, false], negate: true
    assert_equal true, proc.call
  end

  test "wraps callable without negate" do
    proc = StepperMotor.wrap_conditional(-> { :foo })
    assert_equal true, proc.call

    proc = StepperMotor.wrap_conditional(-> { nil })
    assert_equal false, proc.call

    proc = StepperMotor.wrap_conditional(-> { false })
    assert_equal false, proc.call

    proc = StepperMotor.wrap_conditional(-> { true })
    assert_equal true, proc.call
  end

  test "wraps callable with negate" do
    proc = StepperMotor.wrap_conditional(-> { :foo }, negate: true)
    assert_equal false, proc.call

    proc = StepperMotor.wrap_conditional(-> { nil }, negate: true)
    assert_equal true, proc.call

    proc = StepperMotor.wrap_conditional(-> { false }, negate: true)
    assert_equal true, proc.call

    proc = StepperMotor.wrap_conditional(-> { true }, negate: true)
    assert_equal false, proc.call
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

    cond = StepperMotor.wrap_conditional(:should_do?)
    assert_equal true, doer.instance_exec(&cond)

    not_doer = NotDoer.new
    assert_equal false, not_doer.instance_exec(&cond)
  end

  test "wraps method with negate" do
    doer = Doer.new

    cond = StepperMotor.wrap_conditional(:should_do?, negate: true)
    assert_equal false, doer.instance_exec(&cond)

    not_doer = NotDoer.new
    assert_equal true, doer.instance_exec(&cond)
  end
end
