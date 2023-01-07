# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  module Bulk
    Error = Class.new(StandardError)

    thread_mattr_accessor :current_buffer

    # @return [Boolean] Whether the current thread is currently bulk buffering jobs
    def self.capture(active_jobs = nil, queue_adapter = nil)
      if block_given?
        begin
          original_buffer = current_buffer
          self.current_buffer = Buffer.new(active_jobs, queue_adapter)
          yield
        ensure
          self.current_buffer = original_buffer
        end
      else
        current_buffer&.add(active_jobs, queue_adapter)
      end
    end

    def self.capture!(active_jobs = nil, queue_adapter = nil, &block)
      capture(active_jobs, queue_adapter, &block) || raise(Error, 'No bulk capture in progress')
    end

    # @return [Array<ActiveJob::Base>] The ActiveJob instances that have been captured; check provider_job_id to confirm enqueued.
    def self.enqueue(active_jobs = [], queue_adapter = nil)
      if block_given?
        capture(active_jobs, queue_adapter) do
          yield
          enqueue
        end
      else
        buffer = current_buffer || Buffer.new
        Array(active_jobs).each { |active_job| buffer.add(active_job, queue_adapter) }

        buffer.active_jobs_by_queue_adapter.each_pair do |adapter, jobs|
          jobs = jobs.reject(&:provider_job_id)

          if adapter.respond_to?(:enqueue_all)
            adapter.enqueue_all(jobs)
          else
            jobs.each do |active_job|
              active_job.scheduled_at ? adapter.enqueue_at(active_job, active_job.scheduled_at) : adapter.enqueue(active_job)
            end
          end
        end

        buffer.active_jobs
      end
    end

    class Buffer
      def initialize(active_jobs = nil, queue_adapter = nil)
        @values = {}
        Array(active_jobs).each { |active_job| add(active_job, queue_adapter) }
      end

      def add(active_job, queue_adapter = nil)
        queue_adapter ||= active_job.queue_adapter
        raise Error, "Jobs must have a Queue Adapter" if queue_adapter.nil?

        @values[queue_adapter] ||= []
        @values[queue_adapter] << active_job
        true
      end

      def active_jobs_by_queue_adapter
        @values
      end

      def active_jobs
        @values.values.flatten
      end
    end
  end
end
