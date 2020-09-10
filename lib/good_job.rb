require "rails"

require "active_job"
require "active_job/queue_adapters"

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  'cli' => "CLI"
)
loader.push_dir(File.join(__dir__, ["generators"]))
loader.setup

require "good_job/railtie"

# GoodJob is a multithreaded, Postgres-based, ActiveJob backend for Ruby on Rails.
#
# +GoodJob+ is the top-level namespace and exposes configuration attributes.
module GoodJob
  # @!attribute [rw] logger
  #   @!scope class
  #   The logger used by GoodJob (default: +Rails.logger+).
  #   Use this to redirect logs to a special location or file.
  #   @return [Logger]
  #   @example Output GoodJob logs to a file:
  #     GoodJob.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
  mattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))

  # @!attribute [rw] preserve_job_records
  #   @!scope class
  #   Whether to preserve job records in the database after they have finished (default: +false+).
  #   By default, GoodJob deletes job records after the job is completed successfully.
  #   If you want to preserve jobs for latter inspection, set this to +true+.
  #   If +true+, you will need to clean out jobs using the +good_job cleanup_preserved_jobs+ CLI command.
  #   @return [Boolean]
  mattr_accessor :preserve_job_records, default: false

  # @!attribute [rw] reperform_jobs_on_standard_error
  #   @!scope class
  #   Whether to re-perform a job when a type of +StandardError+ is raised to GoodJob (default: +true+).
  #   If +true+, causes jobs to be re-queued and retried if they raise an instance of +StandardError+.
  #   If +false+, jobs will be discarded or marked as finished if they raise an instance of +StandardError+.
  #   Instances of +Exception+, like +SIGINT+, will *always* be retried, regardless of this attribute's value.
  #   @return [Boolean]
  mattr_accessor :reperform_jobs_on_standard_error, default: true

  # @!attribute [rw] on_thread_error
  #   @!scope class
  #   This callable will be called when an exception reaches GoodJob (default: +nil+).
  #   It can be useful for logging errors to bug tracking services, like Sentry or Airbrake.
  #   @example Send errors to Sentry
  #     # config/initializers/good_job.rb
  #     GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
  #   @return [#call, nil]
  mattr_accessor :on_thread_error, default: nil

  # Stop executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # @param wait [Boolean] whether to wait for shutdown
  # @return [void]
  def self.shutdown(wait: true)
    Notifier.instances.each { |notifier| notifier.shutdown(wait: wait) }
    Scheduler.instances.each { |scheduler| scheduler.shutdown(wait: wait) }
  end

  # Tests whether jobs have stopped executing.
  # @return [Boolean] whether background threads are shut down
  def self.shutdown?
    Notifier.instances.all?(&:shutdown?) && Scheduler.instances.all?(&:shutdown?)
  end

  # Stops and restarts executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # @return [void]
  def self.restart
    Notifier.instances.each(&:restart)
    Scheduler.instances.each(&:restart)
  end

  ActiveSupport.run_load_hooks(:good_job, self)
end
