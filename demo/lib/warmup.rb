# frozen_string_literal: true

# Renders representative pages once in the Puma master before it forks,
# so compiled templates, loaded schema, and lazily-initialized state are
# shared copy-on-write by the workers instead of being rebuilt in each one.
# See https://dev.37signals.com/warming-up-the-puma-master-before-it-forks/
module Warmup
  PATHS = %w[
    /good_job/jobs
    /good_job/batches
    /good_job/cron_entries
    /good_job/processes
    /good_job/performance
    /good_job/pauses
    /good_job/cleaner
    /good_job/jobs/metrics/primary_nav
    /good_job/jobs/metrics/job_status
  ].freeze

  # @return [Hash{String => Integer}] response status by path
  def self.run(app)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    request = Rack::MockRequest.new(app)
    statuses = paths.index_with { |path| request.get(path, "REMOTE_ADDR" => "127.0.0.1").status }
    Rack::Attack.reset! if defined?(Rack::Attack)

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    failed = statuses.reject { |_path, status| status == 200 }
    Rails.logger.info("Warmed up #{statuses.size} pages in #{duration.round(2)}s")
    Rails.logger.warn("Warmup pages did not succeed: #{failed}") if failed.any?
    statuses
  rescue StandardError => e
    Rails.logger.warn("Warmup failed: #{e.class}: #{e.message}")
    {}
  ensure
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
  end

  def self.paths
    paths = PATHS.dup
    if (execution = GoodJob::Execution.order(created_at: :desc).first)
      paths << "/good_job/jobs/#{execution.active_job_id}"
      paths << "/good_job/jobs/#{execution.active_job_id}/executions/#{execution.id}"
    end
    paths << "/good_job/cron_entries/#{GoodJob.configuration.cron_entries.first.key}" if GoodJob.configuration.cron_entries.any?
    paths
  end
end
