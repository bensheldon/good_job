# frozen_string_literal: true

module GoodJob
  # Execution-local storage with a compatibility fallback.
  # Uses ActiveSupport::IsolatedExecutionState on Rails 7.0+ (which respects
  # config.active_support.isolation_level = :fiber for Fiber-aware servers).
  # Falls back to Thread.current on older Rails.
  module SafeState
    def self.[](key)
      state[key]
    end

    def self.[]=(key, value)
      state[key] = value
    end

    def self.delete(key)
      if defined?(ActiveSupport::IsolatedExecutionState)
        ActiveSupport::IsolatedExecutionState.delete(key)
      else
        Thread.current[key] = nil
      end
    end

    def self.state
      if defined?(ActiveSupport::IsolatedExecutionState)
        ActiveSupport::IsolatedExecutionState
      else
        Thread.current
      end
    end
    private_class_method :state
  end
end
