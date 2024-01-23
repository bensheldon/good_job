# frozen_string_literal: true

require "active_job"
require "active_job/queue_adapters"

require "good_job/version"
require "good_job/engine"

require "good_job/adapter"
require "active_job/queue_adapters/good_job_adapter"
require "good_job/active_job_extensions/batches"
require "good_job/active_job_extensions/concurrency"
require "good_job/interrupt_error"
require "good_job/active_job_extensions/interrupt_errors"
require "good_job/active_job_extensions/labels"
require "good_job/active_job_extensions/notify_options"

require "good_job/assignable_connection"
require "good_job/bulk"
require "good_job/callable"
require "good_job/capsule"
require "good_job/cleanup_tracker"
require "good_job/cli"
require "good_job/configuration"
require "good_job/cron_manager"
require "good_job/current_thread"
require "good_job/daemon"
require "good_job/dependencies"
require "good_job/job_performer"
require "good_job/job_performer/metrics"
require "good_job/log_subscriber"
require "good_job/multi_scheduler"
require "good_job/notifier"
require "good_job/poller"
require "good_job/probe_server"
require "good_job/probe_server/healthcheck_middleware"
require "good_job/probe_server/not_found_app"
require "good_job/probe_server/simple_handler"
require "good_job/probe_server/webrick_handler"
require "good_job/scheduler"
require "good_job/shared_executor"
require "good_job/systemd_service"

# GoodJob is a multithreaded, Postgres-based, ActiveJob backend for Ruby on Rails.
#
# +GoodJob+ is the top-level namespace and exposes configuration attributes.
module GoodJob
  include GoodJob::Dependencies

  # Default, null, blank value placeholder.
  NONE = Module.new.freeze

  # Default logger for GoodJob; overridden by Rails.logger in Railtie.
  DEFAULT_LOGGER = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))

  # @!attribute [rw] active_record_parent_class
  #   @!scope class
  #   The ActiveRecord parent class inherited by +GoodJob::Execution+ (default: +ActiveRecord::Base+).
  #   Use this when using multiple databases or other custom ActiveRecord configuration.
  #   @return [ActiveRecord::Base]
  #   @example Change the base class:
  #     GoodJob.active_record_parent_class = "CustomApplicationRecord"
  mattr_accessor :active_record_parent_class, default: nil

  # @!attribute [rw] logger
  #   @!scope class
  #   The logger used by GoodJob (default: +Rails.logger+).
  #   Use this to redirect logs to a special location or file.
  #   @return [Logger, nil]
  #   @example Output GoodJob logs to a file:
  #     GoodJob.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
  mattr_accessor :logger, default: DEFAULT_LOGGER

  # @!attribute [rw] preserve_job_records
  #   @!scope class
  #   Whether to preserve job records in the database after they have finished (default: +true+).
  #   If you want to preserve jobs for latter inspection, set this to +true+.
  #   If you want to preserve only jobs that finished with error for latter inspection, set this to +:on_unhandled_error+.
  #   If you do not want to preserve jobs, set this to +false+.
  #   When using GoodJob's cron functionality, job records will be preserved for a brief time to prevent duplicate jobs.
  #   @return [Boolean, Symbol, nil]
  mattr_accessor :preserve_job_records, default: true

  # @!attribute [rw] retry_on_unhandled_error
  #   @!scope class
  #   Whether to re-perform a job when a type of +StandardError+ is raised to GoodJob (default: +false+).
  #   If +true+, causes jobs to be re-queued and retried if they raise an instance of +StandardError+.
  #   If +false+, jobs will be discarded or marked as finished if they raise an instance of +StandardError+.
  #   Instances of +Exception+, like +SIGINT+, will *always* be retried, regardless of this attribute's value.
  #   @return [Boolean, nil]
  mattr_accessor :retry_on_unhandled_error, default: false

  # @!attribute [rw] on_thread_error
  #   @!scope class
  #   This callable will be called when an exception reaches GoodJob (default: +nil+).
  #   It can be useful for logging errors to bug tracking services, like Sentry or Airbrake.
  #   @example Send errors to Sentry
  #     # config/initializers/good_job.rb
  #     GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
  #   @return [Proc, nil]
  mattr_accessor :on_thread_error, default: nil

  # @!attribute [rw] configuration
  #   @!scope class
  #   Global configuration object for GoodJob.
  #   @return [GoodJob::Configuration, nil]
  mattr_accessor :configuration, default: GoodJob::Configuration.new({})

  # @!attribute [rw] capsule
  #   @!scope class
  #   Global/default execution capsule for GoodJob.
  #   @return [GoodJob::Capsule, nil]
  mattr_accessor :capsule, default: GoodJob::Capsule.new(configuration: configuration)

  # Called with exception when a GoodJob thread raises an exception
  # @param exception [Exception] Exception that was raised
  # @return [void]
  def self._on_thread_error(exception)
    on_thread_error.call(exception) if on_thread_error.respond_to?(:call)
  end

  # Custom Active Record configuration that is class_eval'ed into +GoodJob::BaseRecord+
  # @param block Custom Active Record configuration
  # @return [void]
  #
  # @example
  #   GoodJob.configure_active_record do
  #     connects_to database: :special_database
  #   end
  def self.configure_active_record(&block)
    self._active_record_configuration = block
  end
  mattr_accessor :_active_record_configuration, default: nil

  # Stop executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # @param timeout [nil, Numeric] Seconds to wait for actively executing jobs to finish
  #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
  #   * +-1+, the scheduler will wait until the shutdown is complete.
  #   * +0+, the scheduler will immediately shutdown and stop any active tasks.
  #   * +1..+, the scheduler will wait that many seconds before stopping any remaining active tasks.
  # @return [void]
  def self.shutdown(timeout: -1)
    _shutdown_all(Capsule.instances, timeout: timeout)
  end

  # Tests whether jobs have stopped executing.
  # @return [Boolean] whether background threads are shut down
  def self.shutdown?
    Capsule.instances.all?(&:shutdown?)
  end

  # Stops and restarts executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # @param timeout [Numeric] Seconds to wait for active threads to finish.
  # @return [void]
  def self.restart(timeout: -1)
    return if configuration.execution_mode != :async && configuration.in_webserver?

    _shutdown_all(Capsule.instances, :restart, timeout: timeout)
  end

  # Sends +#shutdown+ or +#restart+ to executable objects ({GoodJob::Notifier}, {GoodJob::Poller}, {GoodJob::Scheduler}, {GoodJob::MultiScheduler}, {GoodJob::CronManager})
  # @param executables [Array<Notifier, Poller, Scheduler, MultiScheduler, CronManager>] Objects to shut down.
  # @param method_name [:symbol] Method to call, e.g. +:shutdown+ or +:restart+.
  # @param timeout [nil,Numeric]
  # @return [void]
  def self._shutdown_all(executables, method_name = :shutdown, timeout: -1)
    if timeout.is_a?(Numeric) && timeout.positive?
      executables.each { |executable| executable.send(method_name, timeout: nil) }

      stop_at = Time.current + timeout
      executables.each { |executable| executable.send(method_name, timeout: [stop_at - Time.current, 0].max) }
    else
      executables.each { |executable| executable.send(method_name, timeout: timeout) }
    end
  end

  # Destroys preserved job and batch records.
  # By default, GoodJob destroys job records when the job is performed and this
  # method is not necessary. However, when `GoodJob.preserve_job_records = true`,
  # the jobs will be preserved in the database. This is useful when wanting to
  # analyze or inspect job performance.
  # If you are preserving job records this way, use this method regularly to
  # destroy old records and preserve space in your database.
  # @param older_than [nil,Numeric,ActiveSupport::Duration] Jobs older than this will be destroyed (default: +86400+).
  # @return [Integer] Number of job execution records and batches that were destroyed.
  def self.cleanup_preserved_jobs(older_than: nil, in_batches_of: 1_000)
    older_than ||= GoodJob.configuration.cleanup_preserved_jobs_before_seconds_ago
    timestamp = Time.current - older_than
    include_discarded = GoodJob.configuration.cleanup_discarded_jobs?

    ActiveSupport::Notifications.instrument("cleanup_preserved_jobs.good_job", { older_than: older_than, timestamp: timestamp }) do |payload|
      deleted_executions_count = 0
      deleted_batches_count = 0
      deleted_discrete_executions_count = 0

      jobs_query = GoodJob::Job.where('finished_at <= ?', timestamp).order(finished_at: :asc).limit(in_batches_of)
      jobs_query = jobs_query.succeeded unless include_discarded
      loop do
        active_job_ids = jobs_query.pluck(:active_job_id)
        break if active_job_ids.empty?

        if GoodJob::Execution.discrete_support?
          deleted_discrete_executions = GoodJob::DiscreteExecution.where(active_job_id: active_job_ids).delete_all
          deleted_discrete_executions_count += deleted_discrete_executions
        end

        deleted_executions = GoodJob::Execution.where(active_job_id: active_job_ids).delete_all
        deleted_executions_count += deleted_executions
      end

      if GoodJob::BatchRecord.migrated?
        batches_query = GoodJob::BatchRecord.where('finished_at <= ?', timestamp).limit(in_batches_of)
        batches_query = batches_query.succeeded unless include_discarded
        loop do
          deleted = batches_query.delete_all
          break if deleted.zero?

          deleted_batches_count += deleted
        end
      end

      payload[:destroyed_batches_count] = deleted_batches_count
      payload[:destroyed_discrete_executions_count] = deleted_discrete_executions_count
      payload[:destroyed_executions_count] = deleted_executions_count

      destroyed_records_count = deleted_batches_count + deleted_discrete_executions_count + deleted_executions_count
      payload[:destroyed_records_count] = destroyed_records_count

      destroyed_records_count
    end
  end

  # Perform all queued jobs in the current thread.
  # This is primarily intended for usage in a test environment.
  # Unhandled job errors will be raised.
  # @param queue_string [String] Queues to execute jobs from
  # @param limit [Integer, nil] Maximum number of iterations for the loop
  # @return [void]
  def self.perform_inline(queue_string = "*", limit: nil)
    job_performer = JobPerformer.new(queue_string)
    iteration = 0
    loop do
      break if limit && iteration >= limit

      result = Rails.application.executor.wrap { job_performer.next }
      break unless result
      raise result.unhandled_error if result.unhandled_error

      iteration += 1
    end
  end

  # Deprecator for providing deprecation warnings.
  # @return [ActiveSupport::Deprecation]
  def self.deprecator
    @_deprecator ||= begin
      next_major_version = GEM_VERSION.segments[0] + 1
      ActiveSupport::Deprecation.new("#{next_major_version}.0", "GoodJob")
    end
  end

  include ActiveSupport::Deprecation::DeprecatedConstantAccessor
  deprecate_constant :Lockable, 'GoodJob::AdvisoryLockable', deprecator: deprecator

  # Whether all GoodJob migrations have been applied.
  # For use in tests/CI to validate GoodJob is up-to-date.
  # @return [Boolean]
  def self.migrated?
    # Always update with the most recent migration check
    GoodJob::Execution.reset_column_information
    GoodJob::Execution.candidate_lookup_index_migrated?
  end

  ActiveSupport.run_load_hooks(:good_job, self)
end
