# frozen_string_literal: true

module SideEffects
  module TestHelper
    def teardown
      SideEffects.clear!
      super
    end

    def assert_produced_side_effects(*side_effect_names)
      SideEffects.clear!
      yield.tap do
        side_effect_names.each do |side_effect_name|
          assert SideEffects.produced?(side_effect_name), "The side effect named #{side_effect_name.inspect} should have been produced, but wasn't"
        end
      end
    end

    def assert_did_not_produce_side_effects(*side_effect_names)
      SideEffects.clear!
      yield.tap do
        side_effect_names.each do |side_effect_name|
          refute SideEffects.produced?(side_effect_name), "The side effect named #{side_effect_name.inspect} has been produced, but should not have"
        end
      end
    end

    def assert_no_side_effects(*side_effect_names)
      SideEffects.clear!
      yield.tap do
        assert SideEffects.none?, "No side effect should have been produced"
      end
    end
  end

  def self.produced?(name)
    Thread.current[:side_effects].to_h.key?(name.to_s)
  end

  def self.none?
    Thread.current[:side_effects].to_h.empty?
  end

  def self.names
    Thread.current[:side_effects].to_h.keys.map(&:to_s)
  end

  def self.clear!
    Thread.current[:side_effects] = {}
  end

  def self.touch!(name)
    if Thread.current[:side_effects].nil?
      raise <<~ERROR
        The current thread locals do not contain :side_effects, which means that your job
        is running on a different thread than the specs. This is probably due to bad configuration
        of the ActiveJob test adapter.
      ERROR
    end
    Thread.current[:side_effects][name.to_s] = true
  end
end
