# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentThread
    # Resettable accessors for thread-local values.
    ACCESSORS = %i[
      cron_at
      cron_key
      error_on_discard
      error_on_retry
      execution
    ].freeze

    # @!attribute [rw] cron_at
    #   @!scope class
    #   Cron At
    #   @return [DateTime, nil]
    thread_mattr_accessor :cron_at

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
    # @param [Hash] values to assign
    # @return [void]
    def self.reset(values = {})
      ACCESSORS.each do |accessor|
        send("#{accessor}=", values[accessor])
      end
    end

    # Exports values to hash
    # @return [Hash]
    def self.to_h
      ACCESSORS.index_with do |accessor|
        send(accessor)
      end
    end

    # @return [String] UUID of the currently executing GoodJob::Execution
    def self.active_job_id
      execution&.active_job_id
    end

    # @return [Integer] Current process ID
    def self.process_id
      ::Process.pid
    end

    # @return [String] Current thread name
    def self.thread_name
      (Thread.current.name || Thread.current.object_id).to_s
    end

    # Wrap the yielded block with CurrentThread values and reset after the block
    # @yield [self]
    # @return [void]
    def self.within
      original_values = to_h
      yield(self)
    ensure
      reset(original_values)
    end
  end
end
