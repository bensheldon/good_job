# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'

module GoodJob
  module Bulk
    thread_mattr_accessor :jobs

    def self.enqueue(wrap: nil)
      original_jobs = jobs
      self.jobs = []

      yield

      # The `jobs` are tuples of [Adapter, ActiveJob::Base]
      new_jobs = self.jobs
      self.jobs = nil

      enqueuer = lambda do
        jobs_per_adapter = new_jobs.each_with_object({}) do |(adapter, job), h|
          h[adapter] ||= []
          h[adapter] << job
        end
        jobs_per_adapter.each_pair do |adapter, active_jobs|
          adapter.enqueue_all(active_jobs)
        end
      end

      wrap ? wrap.call(new_jobs, &enqueuer) : enqueuer.call
    ensure
      self.jobs = original_jobs
    end

  end
end