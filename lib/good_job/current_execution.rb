require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)

  module CurrentExecution
    # @!attribute [rw] error_on_retry
    #   @!scope class
    #   Error captured by retry_on
    #   @return [Exception, nil]
    thread_mattr_accessor :error_on_retry

    # @!attribute [rw] error_on_discard
    #   @!scope class
    #   Error captured by discard_on
    #   @return [Exception, nil]
    thread_mattr_accessor :error_on_discard

    # Resets attributes
    # @return [void]
    def self.reset
      self.error_on_retry = nil
      self.error_on_discard = nil
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
