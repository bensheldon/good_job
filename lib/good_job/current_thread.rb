# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentThread
    # @!attribute [rw] cron_key
    #   @!scope class
    #   Cron Key
    #   @return [String, nil]
    thread_mattr_accessor :cron_key

    # @!attribute [rw] error_on_discard
    #   @!scope class
    #   Error captured by discard_on
    #   @return [Exception, nil]
    thread_mattr_accessor :error_on_discard

    # @!attribute [rw] error_on_retry
    #   @!scope class
    #   Error captured by retry_on
    #   @return [Exception, nil]
    thread_mattr_accessor :error_on_retry

    # @!attribute [rw] executions
    #   @!scope class
    #   Execution
    #   @return [GoodJob::Execution, nil]
    thread_mattr_accessor :execution

    # Resets attributes
    # @return [void]
    def self.reset
      self.cron_key = nil
      self.execution = nil
      self.error_on_discard = nil
      self.error_on_retry = nil
    end

    # @return [String] UUID of the currently executing GoodJob::Execution
    def self.active_job_id
      execution&.active_job_id
    end

    # @return [Integer] Current process ID
    def self.process_id
      Process.pid
    end

    # @return [String] Current thread name
    def self.thread_name
      (Thread.current.name || Thread.current.object_id).to_s
    end

    # @return [void]
    def self.within
      reset
      yield(self)
    ensure
      reset
    end
  end
end
