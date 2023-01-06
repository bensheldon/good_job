# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  module Bulk
    thread_mattr_accessor :jobs

    def self.enqueue(wrap: nil)
      original_jobs = jobs
      self.jobs = []

      yield

      new_jobs = jobs
      self.jobs = nil

      enqueuer = lambda do
        new_jobs_per_adapter = new_jobs.group_by(&:adapter)
        new_jobs_per_adapter.each_pair do |adapter, jobs_for_adapter|
          if adapter.respond_to?(:enqueue_all)
            # `enqueue_all` does not support "scheduled_at"
            just_jobs = jobs_for_adapter.map {|j| j[1] }
            adapter.enqueue_all(just_jobs)
          else
            jobs_for_adapter.each do |(_adapter, active_job, scheduled_at)|
              adapter.enqueue_all(active_job, scheduled_at)
            end
          end
        end
      end

      wrap ? wrap.call(new_jobs, &enqueuer) : enqueuer.call
    ensure
      self.jobs = original_jobs
    end
  end
end