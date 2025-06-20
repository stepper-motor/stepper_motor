# frozen_string_literal: true

module StepperMotor
  # A wrapper for conditional logic that can be evaluated against an object.
  # This class encapsulates different types of conditions (booleans, symbols, callables, arrays)
  # and provides a unified interface for checking if a condition is satisfied by a given object.
  # It handles negation and ensures proper context when evaluating conditions.
  class Conditional
    def initialize(condition, negate: false)
      @condition = condition
      @negate = negate
      validate_condition
    end

    def satisfied_by?(object)
      result = case @condition
      when Array
        @condition.all? { |c| Conditional.new(c).satisfied_by?(object) }
      when Symbol
        !!object.send(@condition)
      when Conditional
        @condition.satisfied_by?(object)
      else
        if @condition.respond_to?(:call)
          !!object.instance_exec(&@condition)
        else
          !!@condition
        end
      end

      @negate ? !result : result
    end

    private

    def validate_condition
      unless [true, false, nil].include?(@condition) || @condition.is_a?(Symbol) || @condition.is_a?(Array) || @condition.is_a?(Conditional) || @condition.respond_to?(:call)
        raise ArgumentError, "condition must be a boolean, nil, Symbol, Array, Conditional or a callable object, but was a #{@condition.inspect}"
      end
    end
  end
end
