# frozen_string_literal: true

# Exercises the app once in the Puma master before it forks, so compiled
# templates, loaded schema, and lazily-initialized state are shared
# copy-on-write by the workers instead of being rebuilt in each one.
# See https://dev.37signals.com/warming-up-the-puma-master-before-it-forks/
module Warmup
  BUDGET = 15 # seconds

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

  # Links to follow from a rendered page, so detail pages are warmed up the way a browser would reach them
  FOLLOW = {
    "/good_job/jobs" => %r{href="(/good_job/jobs/[0-9a-f-]{36}[^"]*)"},
    "/good_job/cron_entries" => %r{href="(/good_job/cron_entries/[^/"?]+[^/"]*)"},
  }.freeze
  FRAME_SRC = %r{<turbo-frame[^>]* src="([^"]+)"}

  # @return [Hash{String => Integer}] response status by path
  def self.run(app)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    deadline = started_at + BUDGET
    expired = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline }

    precompile_templates
    statuses = visit_pages(app, expired)
    load_schemas(expired)
    Rack::Attack.reset! if defined?(Rack::Attack)

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    failed = statuses.reject { |_path, status| status == 200 }
    Rails.logger.info("Warmed up #{statuses.size} pages in #{duration.round(2)}s")
    Rails.logger.warn("Warmup pages did not succeed: #{failed}") if failed.any?
    Rails.logger.warn("Warmup stopped early after #{BUDGET}s") if expired.call
    statuses
  rescue StandardError => e
    Rails.logger.warn("Warmup failed: #{e.class}: #{e.message}")
    {}
  ensure
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
  end

  # Compile every template up front, including ones the visited pages don't render
  def self.precompile_templates
    require "actionview_precompiler"
    ActionviewPrecompiler.precompile do |precompiler|
      ActionController::Base.view_paths.each { |view_path| precompiler.scan_view_dir(view_path.path) }
      [Rails.root, GoodJob::Engine.root].each do |root|
        precompiler.scan_controller_dir(root.join("app/controllers").to_s)
        precompiler.scan_helper_dir(root.join("app/helpers").to_s)
      end
    end
  end

  def self.visit_pages(app, expired)
    request = Rack::MockRequest.new(app)
    statuses = {}
    visit = lambda do |path|
      response = request.get(CGI.unescapeHTML(path), "REMOTE_ADDR" => "127.0.0.1")
      statuses[path] = response.status
      response.body
    end

    PATHS.each do |path|
      break if expired.call

      body = visit.call(path)
      next unless FOLLOW[path]

      # Follow a few links until reaching a page with lazy-loaded frames (e.g. a job that has executions)
      body.scan(FOLLOW[path]).flatten.uniq.first(3).each do |link|
        frame_src = visit.call(link)[FRAME_SRC, 1]
        next unless frame_src

        visit.call(frame_src)
        break
      end
    end
    statuses
  end

  # Load the schema of models the visited pages didn't touch
  def self.load_schemas(expired)
    ActiveRecord::Base.connection_pool.with_connection do
      ActiveRecord::Base.descendants.reject(&:abstract_class?).each do |model|
        break if expired.call

        model.columns_hash if model.table_exists?
      end
    end
  end
end
