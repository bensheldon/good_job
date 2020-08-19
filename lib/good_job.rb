require "rails"
require 'good_job/railtie'

require 'good_job/configuration'
require 'good_job/log_subscriber'
require 'good_job/lockable'
require 'good_job/job'
require 'good_job/scheduler'
require 'good_job/multi_scheduler'
require 'good_job/adapter'
require 'good_job/pg_locks'
require 'good_job/performer'
require 'good_job/current_execution'
require 'good_job/notifier'

require 'active_job/queue_adapters/good_job_adapter'

module GoodJob
  mattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
  mattr_accessor :preserve_job_records, default: false
  mattr_accessor :reperform_jobs_on_standard_error, default: true
  mattr_accessor :on_thread_error, default: nil

  ActiveSupport.run_load_hooks(:good_job, self)

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
end
