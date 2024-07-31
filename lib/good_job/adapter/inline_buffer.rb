# frozen_string_literal: true

require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  class Adapter
    # The InlineBuffer is integrated into the Adapter and captures jobs that have been enqueued inline.
    # The purpose is allow job records to be persisted, in a locked state, while within a transaction,
    # and then execute the jobs after the transaction has been committed to ensure that the jobs
    # do not run within a transaction.
    #
    # @private This is intended for internal GoodJob usage only.
    class InlineBuffer
      # @!attribute [rw] current_buffer
      #   @!scope class
      #   Current buffer of jobs to be enqueued.
      #   @return [GoodJob::Adapter::InlineBuffer, nil]
      thread_mattr_accessor :current_buffer

      # This block should be used to wrap the transaction that could enqueue jobs.
      # @yield The block that may enqueue jobs.
      # @return [Proc] A proc that will execute enqueued jobs after the transaction has been committed.
      # @example Wrapping a transaction
      #   buffer = GoodJob::Adapter::InlineBuffer.capture do
      #     ActiveRecord::Base.transaction do
      #       MyJob.perform_later
      #     end
      #   end
      #   buffer.call
      def self.capture
        if current_buffer
          yield
          return proc {}
        end

        begin
          self.current_buffer = new
          yield
          current_buffer.to_proc
        ensure
          self.current_buffer = nil
        end
      end

      # Used within the adapter to wrap inline job execution
      def self.perform_now_or_defer(&block)
        if defer?
          current_buffer.defer(block)
        else
          yield
        end
      end

      def self.defer?
        current_buffer.present?
      end

      def initialize
        @callables = []
      end

      def defer(callable)
        @callables << callable
      end

      def to_proc
        proc do
          @callables.map(&:call)
        end
      end
    end
  end
end
