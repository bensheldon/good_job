# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  module Bulk
    Error = Class.new(StandardError)

    # @!attribute [rw] current_buffer
    #   @!scope class
    #   Current buffer of jobs to be enqueued.
    #   @return [GoodJob::Bulk::Buffer, nil]
    thread_mattr_accessor :current_buffer

    # Capture jobs to a buffer. Pass either a block, or specific Active Jobs to be buffered.
    # @param active_jobs [Array<ActiveJob::Base>] Active Jobs to be buffered.
    # @param queue_adapter Override the jobs implict queue adapter with an explicit one.
    # @return [nil, Array<ActiveJob::Base>] The ActiveJob instances that have been buffered; nil if no active buffer
    def self.capture(active_jobs = nil, queue_adapter: nil)
      raise(ArgumentError, "Use either the block form or the argument form, not both") if block_given? && active_jobs

      if block_given?
        begin
          original_buffer = current_buffer
          self.current_buffer = Buffer.new
          yield
          current_buffer.active_jobs
        ensure
          self.current_buffer = original_buffer
        end
      else
        current_buffer&.add(active_jobs, queue_adapter: queue_adapter)
      end
    end

    # Capture jobs to a buffer and enqueue them all at once; or enqueue the current buffer.
    # @param active_jobs [Array<ActiveJob::Base>] Active Jobs to be enqueued.
    # @return [Array<ActiveJob::Base>] The ActiveJob instances that have been captured; check provider_job_id to confirm enqueued.
    def self.enqueue(active_jobs = nil)
      raise(ArgumentError, "Use either the block form or the argument form, not both") if block_given? && active_jobs

      if block_given?
        capture do
          yield
          current_buffer&.enqueue
        end
      elsif active_jobs.present?
        buffer = Buffer.new
        buffer.add(active_jobs)
        buffer.enqueue
        buffer.active_jobs
      elsif current_buffer.present?
        current_buffer.enqueue
        current_buffer.active_jobs
      end
    end

    # Temporarily unset the current buffer; used to enqueue buffered jobs.
    # @return [void]
    def self.unbuffer
      original_buffer = current_buffer
      self.current_buffer = nil
      yield
    ensure
      self.current_buffer = original_buffer
    end

    class Buffer
      def initialize
        @values = []
      end

      def add(active_jobs, queue_adapter: nil)
        new_pairs = Array(active_jobs).map do |active_job|
          adapter = queue_adapter || active_job.class.queue_adapter
          raise Error, "Jobs must have a Queue Adapter" unless adapter

          [active_job, adapter]
        end
        @values.append(*new_pairs)

        true
      end

      def enqueue
        Bulk.unbuffer do
          active_jobs_by_queue_adapter.each do |adapter, jobs|
            jobs = jobs.reject(&:provider_job_id) # Do not re-enqueue already enqueued jobs

            if adapter.respond_to?(:enqueue_all)
              unbulkable_jobs, bulkable_jobs = jobs.partition do |job|
                job.respond_to?(:good_job_concurrency_key) && job.good_job_concurrency_key &&
                  (job.class.good_job_concurrency_config[:enqueue_limit] || job.class.good_job_concurrency_config[:total_limit])
              end
              adapter.enqueue_all(bulkable_jobs) if bulkable_jobs.any?
            else
              unbulkable_jobs = jobs
            end

            unbulkable_jobs.each do |job|
              job.enqueue
            rescue GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError
              # ignore
            end
          end
        end
      end

      def active_jobs_by_queue_adapter
        @values.each_with_object({}) do |(job, adapter), memo|
          memo[adapter] ||= []
          memo[adapter] << job
        end
      end

      def active_jobs
        @values.map(&:first)
      end
    end
  end
end
