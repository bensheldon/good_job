require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentExecution
    # @!attribute [rw] active_job_id
    #   @!scope class
    #   ActiveJob ID
    #   @return [String, nil]
    thread_mattr_accessor :active_job_id

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

    # Resets attributes
    # @return [void]
    def self.reset
      self.active_job_id = nil
      self.error_on_discard = nil
      self.error_on_retry = nil
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
