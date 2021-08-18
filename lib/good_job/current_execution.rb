# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentExecution
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

    # @!attribute [rw] good_job
    #   @!scope class
    #   Cron Key
    #   @return [GoodJob::Job, nil]
    thread_mattr_accessor :good_job

    # Resets attributes
    # @return [void]
    def self.reset
      self.cron_key = nil
      self.good_job = nil
      self.error_on_discard = nil
      self.error_on_retry = nil
    end

    # @return [String] UUID of the currently executing GoodJob::Job
    def self.active_job_id
      good_job&.active_job_id
    end

    # @return [Integer] Current process ID
    def self.process_id
      Process.pid
    end

    # @return [String] Current thread name
    def self.thread_name
      (Thread.current.name || Thread.current.object_id).to_s
    end
  end
end
