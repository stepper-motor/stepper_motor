# frozen_string_literal: true

module SideEffects
  module SpecHelper
    def self.included(into)
      into.before(:each) { SideEffects.clear! }
      into.after(:each) { SideEffects.clear! }
      super
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

  RSpec::Matchers.define :have_produced_side_effects_named do |*side_effect_names|
    match(notify_expectation_failures: true) do |actual|
      SideEffects.clear!
      actual.call
      side_effect_names.each do |side_effect_name|
        expect(SideEffects).to be_produced(side_effect_name), "The side effect named #{side_effect_name.inspect} should have been produced, but wasn't"
      end
      true
    end

    def supports_block_expectations?
      true
    end
  end

  RSpec::Matchers.define :not_have_produced_side_effects_named do |*side_effect_names|
    match(notify_expectation_failures: true) do |actual|
      expect(side_effect_names).not_to be_empty

      SideEffects.clear!
      actual.call

      side_effect_names.each do |side_effect_name|
        expect(SideEffects).not_to be_produced(side_effect_name), "The side effect named #{side_effect_name.inspect} should not have been produced, but was"
      end

      true
    end

    def supports_block_expectations?
      true
    end
  end

  RSpec::Matchers.define :not_have_produced_any_side_effects do
    match(notify_expectation_failures: true) do |actual|
      SideEffects.clear!
      actual.call
      expect(SideEffects).to be_none
      true
    end

    def supports_block_expectations?
      true
    end
  end
end
