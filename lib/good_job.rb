require "rails"
require 'good_job/railtie'

require 'good_job/configuration'
require 'good_job/log_subscriber'
require 'good_job/lockable'
require 'good_job/job'
require 'good_job/scheduler'
require 'good_job/multi_scheduler'
require 'good_job/adapter'
require 'good_job/performer'
require 'good_job/current_execution'
require 'good_job/notifier'

require 'active_job/queue_adapters/good_job_adapter'

# GoodJob is a multithreaded, Postgres-based, ActiveJob backend for Ruby on Rails.
#
# +GoodJob+ is the top-level namespace and exposes configuration attributes.
module GoodJob
  # @!attribute [rw] logger
  #   @!scope class
  #   The logger used by GoodJob
  #   @return [Logger]
  mattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))

  # @!attribute [rw] preserve_job_records
  #   @!scope class
  #   Whether to preserve job records in the database after they have finished for inspection
  #   @return [Boolean]
  mattr_accessor :preserve_job_records, default: false

  # @!attribute [rw] reperform_jobs_on_standard_error
  #   @!scope class
  #   Whether to re-perform a job when a type of +StandardError+ is raised and bubbles up to the GoodJob backend
  #   @return [Boolean]
  mattr_accessor :reperform_jobs_on_standard_error, default: true

  # @!attribute [rw] on_thread_error
  #   @!scope class
  #   Called when a thread raises an error
  #   @example Send errors to Sentry
  #     # config/initializers/good_job.rb
  #
  #     # With Sentry (or Bugsnag, Airbrake, Honeybadger, etc.)
  #     GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
  #   @return [#call, nil]
  mattr_accessor :on_thread_error, default: nil

  # Shuts down all execution pools
  # @param wait [Boolean] whether to wait for shutdown
  # @return [void]
  def self.shutdown(wait: true)
    Notifier.instances.each { |adapter| adapter.shutdown(wait: wait) }
    Scheduler.instances.each { |scheduler| scheduler.shutdown(wait: wait) }
  end

  # Tests if execution pools are shut down
  # @return [Boolean] whether execution pools are shut down
  def self.shutdown?
    Notifier.instances.all?(&:shutdown?) && Scheduler.instances.all?(&:shutdown?)
  end

  # Restarts all execution pools
  # @return [void]
  def self.restart
    Notifier.instances.each(&:restart)
    Scheduler.instances.each(&:restart)
  end

  ActiveSupport.run_load_hooks(:good_job, self)
end
