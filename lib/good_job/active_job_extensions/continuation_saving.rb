# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    # Periodically saves the progress of an Active Job continuation
    # (+ActiveJob::Continuable+) while it performs, so that if the process exits
    # without a graceful shutdown (e.g. +SIGKILL+ or running out of memory), the
    # job resumes from a recent checkpoint rather than from its last graceful
    # interruption. Work done after the last save is performed again, so each
    # unit of work must be idempotent.
    #
    # At a checkpoint, after Active Job has checked that the job should not stop,
    # the progress is saved if at least +good_job_continuation_save_interval+
    # seconds have passed since the job started or was last saved.
    #
    # @example
    #   class MyJob < ApplicationJob
    #     include ActiveJob::Continuable
    #     include GoodJob::ActiveJobExtensions::ContinuationSaving
    #
    #     # Save progress at most every 30 seconds (default: 5)
    #     self.good_job_continuation_save_interval = 30.seconds
    #   end
    #
    module ContinuationSaving
      extend ActiveSupport::Concern

      # Intervals are randomly lengthened by up to this proportion, so that jobs that
      # started together (e.g. after a deploy) don't keep saving in lockstep.
      JITTER = 0.15
      # Keys of serialized job data that record the progress of a continuation.
      CONTINUATION_KEYS = %w[continuation resumptions attributes].freeze

      included do
        # @!attribute [rw] good_job_continuation_save_interval
        #   @!scope class
        #   Minimum number of seconds (or an +ActiveSupport::Duration+) between saves of
        #   the continuation's progress. +false+ or +0+ disables periodic saving.
        #   @return [Numeric, ActiveSupport::Duration, false]
        class_attribute :good_job_continuation_save_interval, instance_accessor: false, instance_predicate: false, default: 5

        before_perform do
          interval = self.class.good_job_continuation_save_interval
          next unless interval.present? && interval.to_f.positive?

          @good_job_continuation_saver = ThrottledBlock.new(interval.to_f, jitter: JITTER) { good_job_save_continuation }
        end

        # Prepended so the save runs after Active Job's own checkpoint, whichever
        # order this module and ActiveJob::Continuable were included in.
        prepend Checkpoint
      end

      private

      # @return [Boolean] whether the progress was saved
      def good_job_save_continuation
        job = GoodJob::CurrentThread.job
        return false unless job && job.active_job_id == job_id

        job.update_serialized_params(serialize.slice(*CONTINUATION_KEYS))
      rescue StandardError => e
        GoodJob._on_thread_error(e)
        false
      end

      # Wraps +ActiveJob::Continuable#checkpoint!+, which Active Job calls at every
      # checkpoint, the same way Active Record's railtie wraps it to reject
      # checkpoints inside a transaction. +super+ raises if the job is stopping
      # (or a transaction is open), so progress is only saved when the job continues.
      module Checkpoint
        def checkpoint!
          super
          # Stop saving once a save fails, e.g. because this execution no longer owns the job
          @good_job_continuation_saver = nil if @good_job_continuation_saver&.call == false
        end
      end

      # Calls a block at most once per interval, measured with the monotonic clock
      # since it was created or the block was last called. Each interval can be
      # randomly lengthened, so that instances created at the same time (e.g. after
      # a deploy) don't keep calling their blocks in lockstep.
      #
      # An instance is not thread-safe.
      class ThrottledBlock
        # @param interval [Numeric] minimum number of seconds between calls of the block
        # @param jitter [Float] proportion by which each interval is randomly lengthened, e.g. +0.15+ for up to 15%
        # @yield the block to throttle, with the arguments passed to {#call}
        def initialize(interval, jitter: 0.0, &block)
          @interval = interval
          @jitter = jitter
          @block = block
          @last_called_at = monotonic_now
          @wait = next_wait
        end

        # Calls the block if at least the interval has elapsed since initialization
        # or the block was last called.
        # @return [Object, nil] the block's return value, or +nil+ if the call was throttled
        def call(...)
          return if monotonic_now - @last_called_at < @wait

          @last_called_at = monotonic_now
          @wait = next_wait
          @block.call(...)
        end

        private

        def next_wait
          @interval * (1 + rand(0..@jitter))
        end

        def monotonic_now
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
      end

      private_constant :JITTER, :CONTINUATION_KEYS, :Checkpoint, :ThrottledBlock
    end
  end
end
