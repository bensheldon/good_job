# frozen_string_literal: true

module GoodJob
  # Execution-local storage with a compatibility fallback.
  # Uses ActiveSupport::IsolatedExecutionState on Rails 7.0+ (which respects
  # config.active_support.isolation_level = :fiber for Fiber-aware servers).
  # Falls back to Thread.current on older Rails.
  module SafeContext
    ISOLATED_EXECUTION_STATE_AVAILABLE = defined?(ActiveSupport::IsolatedExecutionState)

    def self.[](key)
      if ISOLATED_EXECUTION_STATE_AVAILABLE
        ActiveSupport::IsolatedExecutionState[key]
      else
        Thread.current[key]
      end
    end

    def self.[]=(key, value)
      if ISOLATED_EXECUTION_STATE_AVAILABLE
        ActiveSupport::IsolatedExecutionState[key] = value
      else
        Thread.current[key] = value
      end
    end

    def self.delete(key)
      if ISOLATED_EXECUTION_STATE_AVAILABLE
        ActiveSupport::IsolatedExecutionState.delete(key)
      else
        Thread.current[key] = nil
      end
    end
  end
end
