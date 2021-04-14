# typed: strong
# typed: true
module GoodJob
  VERSION = T.let('1.8.0'.freeze, T.untyped)

  class << self
    # The logger used by GoodJob (default: +Rails.logger+).
    # Use this to redirect logs to a special location or file.
    # 
    # Output GoodJob logs to a file:
    # ```ruby
    # GoodJob.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
    # ```
    sig { returns(Logger) }
    attr_accessor :logger

    # Whether to preserve job records in the database after they have finished (default: +false+).
    # By default, GoodJob deletes job records after the job is completed successfully.
    # If you want to preserve jobs for latter inspection, set this to +true+.
    # If you want to preserve only jobs that finished with error for latter inspection, set this to +:on_unhandled_error+.
    # If +true+, you will need to clean out jobs using the +good_job cleanup_preserved_jobs+ CLI command.
    sig { returns(T::Boolean) }
    attr_accessor :preserve_job_records

    # Whether to re-perform a job when a type of +StandardError+ is raised to GoodJob (default: +true+).
    # If +true+, causes jobs to be re-queued and retried if they raise an instance of +StandardError+.
    # If +false+, jobs will be discarded or marked as finished if they raise an instance of +StandardError+.
    # Instances of +Exception+, like +SIGINT+, will *always* be retried, regardless of this attribute's value.
    sig { returns(T::Boolean) }
    attr_accessor :retry_on_unhandled_error

    # This callable will be called when an exception reaches GoodJob (default: +nil+).
    # It can be useful for logging errors to bug tracking services, like Sentry or Airbrake.
    # 
    # Send errors to Sentry
    # ```ruby
    # # config/initializers/good_job.rb
    # GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
    # ```
    sig { returns(T.nilable(Proc)) }
    attr_accessor :on_thread_error
  end

  # 
  # _@deprecated_ — Use {GoodJob#retry_on_unhandled_error} instead.
  sig { returns(T::Boolean) }
  def self.reperform_jobs_on_standard_error; end

  # _@param_ `value`
  # 
  # _@deprecated_ — Use {GoodJob#retry_on_unhandled_error=} instead.
  sig { params(value: T::Boolean).returns(T::Boolean) }
  def self.reperform_jobs_on_standard_error=(value); end

  # Stop executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # 
  # _@param_ `timeout` — Seconds to wait for active threads to finish
  # 
  # _@param_ `wait` — whether to wait for shutdown
  sig { params(timeout: T.nilable(Numeric), wait: T.nilable(T::Boolean)).void }
  def self.shutdown(timeout: -1,, wait: nil); end

  # Tests whether jobs have stopped executing.
  # 
  # _@return_ — whether background threads are shut down
  sig { returns(T::Boolean) }
  def self.shutdown?; end

  # Stops and restarts executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # 
  # _@param_ `timeout` — Seconds to wait for active threads to finish.
  sig { params(timeout: T.nilable(Numeric)).void }
  def self.restart(timeout: -1)); end

  # Sends +#shutdown+ or +#restart+ to executable objects ({GoodJob::Notifier}, {GoodJob::Poller}, {GoodJob::Scheduler})
  # 
  # _@param_ `executables` — Objects to shut down.
  # 
  # _@param_ `method_name` — Method to call, e.g. +:shutdown+ or +:restart+.
  # 
  # _@param_ `timeout`
  sig { params(executables: T::Array[[Notifier, Poller, Scheduler]], method_name: Symbol, timeout: T.nilable(Numeric)).void }
  def self._shutdown_all(executables, method_name = :shutdown, timeout: -1)); end

  # 
  # Implements the +good_job+ command-line tool, which executes jobs and
  # provides other utilities. The actual entry point is in +exe/good_job+, but
  # it just sets up and calls this class.
  # 
  # The +good_job+ command-line tool is based on Thor, a CLI framework for
  # Ruby. For more on general usage, see http://whatisthor.com/ and
  # https://github.com/erikhuda/thor/wiki.
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = T.let(File.expand_path("config/environment.rb"), T.untyped)

    sig { returns(T::Boolean) }
    def self.exit_on_failure?; end

    sig { void }
    def start; end

    # The +good_job + command.
    sig { void }
    def cleanup_preserved_jobs; end
  end

  # 
  # Represents a request to perform an +ActiveJob+ job.
  class Job < ActiveRecord::Base
    include GoodJob::Lockable
    PreviouslyPerformedError = T.let(Class.new(StandardError), T.untyped)
    DEFAULT_QUEUE_NAME = T.let('default'.freeze, T.untyped)
    DEFAULT_PRIORITY = T.let(0, T.untyped)

    # Parse a string representing a group of queues into a more readable data
    # structure.
    # 
    # _@param_ `string` — Queue string
    # 
    # _@return_ — How to match a given queue. It can have the following keys and values:
    # - +{ all: true }+ indicates that all queues match.
    # - +{ exclude: Array<String> }+ indicates the listed queue names should
    #   not match.
    # - +{ include: Array<String> }+ indicates the listed queue names should
    #   match.
    # 
    # ```ruby
    # GoodJob::Job.queue_parser('-queue1,queue2')
    # => { exclude: [ 'queue1', 'queue2' ] }
    # ```
    sig { params(string: String).returns(T::Hash[T.untyped, T.untyped]) }
    def self.queue_parser(string); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs that have not yet been completed.
    sig { returns(ActiveRecord::Relation) }
    def self.unfinished; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs that are not scheduled for a later time than now (i.e. jobs that
    # are not scheduled or scheduled for earlier than the current time).
    sig { returns(ActiveRecord::Relation) }
    def self.only_scheduled; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Order jobs by priority (highest priority first).
    sig { returns(ActiveRecord::Relation) }
    def self.priority_ordered; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Order jobs by scheduled (unscheduled or soonest first).
    sig { returns(ActiveRecord::Relation) }
    def self.schedule_ordered; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs were completed before the given timestamp. If no timestamp is
    # provided, get all jobs that have been completed. By default, GoodJob
    # deletes jobs after they are completed and this will find no jobs.
    # However, if you have changed {GoodJob.preserve_job_records}, this may
    # find completed Jobs.
    # 
    # _@param_ `timestamp` — Get jobs that finished before this time (in epoch time).
    sig { params(timestamp: T.nilable(Float)).returns(ActiveRecord::Relation) }
    def self.finished(timestamp = nil); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs on queues that match the given queue string.
    # 
    # _@param_ `string` — A string expression describing what queues to select. See {Job.queue_parser} or {file:README.md#optimize-queues-threads-and-processes} for more details on the format of the string. Note this only handles individual semicolon-separated segments of that string format.
    sig { params(string: String).returns(ActiveRecord::Relation) }
    def self.queue_string(string); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs in display order with optional keyset pagination.
    # 
    # _@param_ `after_scheduled_at` — Display records scheduled after this time for keyset pagination
    # 
    # _@param_ `after_id` — Display records after this ID for keyset pagination
    sig { params(after_scheduled_at: T.nilable(T.any(DateTime, String)), after_id: T.nilable(T.any(Numeric, String))).returns(ActiveRecord::Relation) }
    def self.display_all(after_scheduled_at: nil, after_id: nil); end

    # Finds the next eligible Job, acquire an advisory lock related to it, and
    # executes the job.
    # 
    # _@return_ — If a job was executed, returns an array with the {Job} record, the
    # return value for the job's +#perform+ method, and the exception the job
    # raised, if any (if the job raised, then the second array entry will be
    # +nil+). If there were no jobs to execute, returns +nil+.
    sig { returns(T.nilable(T::Array[[GoodJob::Job, Object, Exception]])) }
    def self.perform_with_advisory_lock; end

    # Fetches the scheduled execution time of the next eligible Job(s).
    # 
    # _@param_ `after`
    # 
    # _@param_ `limit`
    # 
    # _@param_ `now_limit`
    sig { params(after: T.nilable(DateTime), limit: Integer, now_limit: T.nilable(Integer)).returns(T::Array[[DateTime]]) }
    def self.next_scheduled_at(after: nil, limit: 100, now_limit: nil); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Places an ActiveJob job on a queue by creating a new {Job} record.
    # 
    # _@param_ `active_job` — The job to enqueue.
    # 
    # _@param_ `scheduled_at` — Epoch timestamp when the job should be executed.
    # 
    # _@param_ `create_with_advisory_lock` — Whether to establish a lock on the {Job} record after it is created.
    # 
    # _@return_ — The new {Job} instance representing the queued ActiveJob job.
    sig { params(active_job: ActiveJob::Base, scheduled_at: T.nilable(Float), create_with_advisory_lock: T::Boolean).returns(Job) }
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false); end

    # Execute the ActiveJob job this {Job} represents.
    # 
    # _@return_ — An array of the return value of the job's +#perform+ method and the
    # exception raised by the job, if any. If the job completed successfully,
    # the second array entry (the exception) will be +nil+ and vice versa.
    sig { returns(T::Array[[Object, Exception]]) }
    def perform; end

    # Tests whether this job is safe to be executed by this thread.
    sig { returns(T::Boolean) }
    def executable?; end

    sig { returns(T::Array[[Object, Exception]]) }
    def execute; end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@return_ — whether the lock was acquired.
    sig { returns(T::Boolean) }
    def advisory_lock; end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@return_ — whether the lock was released.
    sig { returns(T::Boolean) }
    def advisory_unlock; end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@return_ — +true+
    sig { returns(T::Boolean) }
    def advisory_lock!; end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { returns(Object) }
    def with_advisory_lock; end

    # Tests whether this record has an advisory lock on it.
    sig { returns(T::Boolean) }
    def advisory_locked?; end

    # Tests whether this record is locked by the current database session.
    sig { returns(T::Boolean) }
    def owns_advisory_lock?; end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    sig { void }
    def advisory_unlock!; end

    # _@param_ `query`
    sig { params(query: String).returns(T::Boolean) }
    def pg_or_jdbc_query(query); end
  end

  # 
  # Manages daemonization of the current process.
  class Daemon
    # _@param_ `pidfile` — Pidfile path
    sig { params(pidfile: T.any(Pathname, String)).void }
    def initialize(pidfile:); end

    # Daemonizes the current process and writes out a pidfile.
    sig { void }
    def daemonize; end

    sig { void }
    def write_pid; end

    sig { void }
    def delete_pid; end

    sig { void }
    def check_pid; end

    # _@param_ `pidfile`
    sig { params(pidfile: T.any(Pathname, String)).returns(Symbol) }
    def pid_status(pidfile); end

    # The path of the generated pidfile.
    sig { returns(T.any(Pathname, String)) }
    attr_reader :pidfile
  end

  # 
  # Pollers regularly wake up execution threads to check for new work.
  class Poller
    DEFAULT_TIMER_OPTIONS = T.let({
  execution_interval: Configuration::DEFAULT_POLL_INTERVAL,
  timeout_interval: 1,
  run_now: true,
}.freeze, T.untyped)

    class << self
      # List of all instantiated Pollers in the current process.
      sig { returns(T::Array[GoodJob::Poller]) }
      attr_reader :instances
    end

    # Creates GoodJob::Poller from a GoodJob::Configuration instance.
    # 
    # _@param_ `configuration`
    sig { params(configuration: GoodJob::Configuration).returns(GoodJob::Poller) }
    def self.from_configuration(configuration); end

    # sord duck - #call looks like a duck type, replacing with untyped
    # _@param_ `recipients`
    # 
    # _@param_ `poll_interval` — number of seconds between polls
    sig { params(recipients: T::Array[T.any(Proc, T.untyped, [Object, Symbol])], poll_interval: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def initialize(*recipients, poll_interval: nil); end

    # Tests whether the timer is running.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Tests whether the timer is shutdown.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # Shut down the notifier.
    # Use {#shutdown?} to determine whether threads have stopped.
    # 
    # _@param_ `timeout` — Seconds to wait for active threads.  * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1)); end

    # Restart the poller.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1)); end

    # Invoked on completion of TimerTask task.
    # 
    # _@param_ `time`
    # 
    # _@param_ `executed_task`
    # 
    # _@param_ `thread_error`
    sig { params(time: Integer, executed_task: Object, thread_error: Exception).void }
    def timer_observer(time, executed_task, thread_error); end

    sig { void }
    def create_timer; end

    # sord duck - #call looks like a duck type, replacing with untyped
    # List of recipients that will receive notifications.
    sig { returns(T::Array[T.any(T.untyped, [Object, Symbol])]) }
    attr_reader :recipients

    # sord warn - Concurrent::TimerTask wasn't able to be resolved to a constant in this project
    sig { returns(Concurrent::TimerTask) }
    attr_reader :timer
  end

  # 
  # ActiveJob Adapter.
  class Adapter
    EXECUTION_MODES = T.let([:async, :async_server, :external, :inline].freeze, T.untyped)

    # _@param_ `execution_mode` — specifies how and where jobs should be executed. You can also set this with the environment variable +GOOD_JOB_EXECUTION_MODE+.  - +:inline+ executes jobs immediately in whatever process queued them (usually the web server process). This should only be used in test and development environments. - +:external+ causes the adapter to enqueue jobs, but not execute them. When using this option (the default for production environments), you'll need to use the command-line tool to actually execute your jobs. - +:async_server+ executes jobs in separate threads within the Rails webserver process (`bundle exec rails server`). It can be more economical for small workloads because you don't need a separate machine or environment for running your jobs, but if your web server is under heavy load or your jobs require a lot of resources, you should choose +:external+ instead.   When not in the Rails webserver, jobs will execute in +:external+ mode to ensure jobs are not executed within `rails console`, `rails db:migrate`, `rails assets:prepare`, etc. - +:async+ executes jobs in any Rails process.  The default value depends on the Rails environment:  - +development+ and +test+: +:inline+ - +production+ and all other environments: +:external+
    # 
    # _@param_ `max_threads` — sets the number of threads per scheduler to use when +execution_mode+ is set to +:async+. The +queues+ parameter can specify a number of threads for each group of queues which will override this value. You can also set this with the environment variable +GOOD_JOB_MAX_THREADS+. Defaults to +5+.
    # 
    # _@param_ `queues` — determines which queues to execute jobs from when +execution_mode+ is set to +:async+. See {file:README.md#optimize-queues-threads-and-processes} for more details on the format of this string. You can also set this with the environment variable +GOOD_JOB_QUEUES+. Defaults to +"*"+.
    # 
    # _@param_ `poll_interval` — sets the number of seconds between polls for jobs when +execution_mode+ is set to +:async+. You can also set this with the environment variable +GOOD_JOB_POLL_INTERVAL+. Defaults to +1+.
    sig do
      params(
        execution_mode: T.nilable(Symbol),
        queues: T.nilable(String),
        max_threads: T.nilable(Integer),
        poll_interval: T.nilable(Integer)
      ).void
    end
    def initialize(execution_mode: nil, queues: nil, max_threads: nil, poll_interval: nil); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Enqueues the ActiveJob job to be performed.
    # For use by Rails; you should generally not call this directly.
    # 
    # _@param_ `active_job` — the job to be enqueued from +#perform_later+
    sig { params(active_job: ActiveJob::Base).returns(GoodJob::Job) }
    def enqueue(active_job); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Enqueues an ActiveJob job to be run at a specific time.
    # For use by Rails; you should generally not call this directly.
    # 
    # _@param_ `active_job` — the job to be enqueued from +#perform_later+
    # 
    # _@param_ `timestamp` — the epoch time to perform the job
    sig { params(active_job: ActiveJob::Base, timestamp: Integer).returns(GoodJob::Job) }
    def enqueue_at(active_job, timestamp); end

    # Shut down the thread pool executors.
    # 
    # _@param_ `timeout` — Seconds to wait for active threads.  * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    # 
    # _@param_ `wait` — Deprecated. Use +timeout:+ instead.
    sig { params(timeout: T.nilable(Numeric), wait: T.nilable(T::Boolean)).void }
    def shutdown(timeout: :default, wait: nil); end

    # Whether in +:async+ execution mode.
    sig { returns(T::Boolean) }
    def execute_async?; end

    # Whether in +:external+ execution mode.
    sig { returns(T::Boolean) }
    def execute_externally?; end

    # Whether in +:inline+ execution mode.
    sig { returns(T::Boolean) }
    def execute_inline?; end

    # Whether running in a web server process.
    sig { returns(T::Boolean) }
    def in_server_process?; end
  end

  # Ruby on Rails integration.
  class Railtie < Rails::Railtie
  end

  # 
  # Adds Postgres advisory locking capabilities to an ActiveRecord record.
  # For details on advisory locks, see the Postgres documentation:
  # - {https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS Advisory Locks Overview}
  # - {https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS Advisory Locks Functions}
  # 
  # @example Add this concern to a +MyRecord+ class:
  #   class MyRecord < ActiveRecord::Base
  #     include Lockable
  # 
  #     def my_method
  #       ...
  #     end
  #   end
  module Lockable
    extend ActiveSupport::Concern
    RecordAlreadyAdvisoryLockedError = T.let(Class.new(StandardError), T.untyped)

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Attempt to acquire an advisory lock on the selected records and
    # return only those records for which a lock could be acquired.
    # 
    # _@return_ — A relation selecting only the records that were locked.
    sig { returns(ActiveRecord::Relation) }
    def self.advisory_lock; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Joins the current query with Postgres's +pg_locks+ table (it provides
    # data about existing locks) such that each row in the main query joins
    # to all the advisory locks associated with that row.
    # 
    # For details on +pg_locks+, see
    # {https://www.postgresql.org/docs/current/view-pg-locks.html}.
    # 
    # Get the records that have a session awaiting a lock:
    # ```ruby
    # MyLockableRecord.joins_advisory_locks.where("pg_locks.granted = ?", false)
    # ```
    sig { returns(ActiveRecord::Relation) }
    def self.joins_advisory_locks; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Find records that do not have an advisory lock on them.
    sig { returns(ActiveRecord::Relation) }
    def self.advisory_unlocked; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Find records with advisory locks owned by the current Postgres
    # session/connection.
    sig { returns(ActiveRecord::Relation) }
    def self.advisory_locked; end

    # Acquires an advisory lock on the selected record(s) and safely releases
    # it after the passed block is completed. The block will be passed an
    # array of the locked records as its first argument.
    # 
    # Note that this will not block and wait for locks to be acquired.
    # Instead, it will acquire a lock on all the selected records that it
    # can (as in {Lockable.advisory_lock}) and only pass those that could be
    # locked to the block.
    # 
    # _@return_ — the result of the block.
    # 
    # Work on the first two +MyLockableRecord+ objects that could be locked:
    # ```ruby
    # MyLockableRecord.order(created_at: :asc).limit(2).with_advisory_lock do |record|
    #   do_something_with record
    # end
    # ```
    sig { returns(Object) }
    def self.with_advisory_lock; end

    sig { returns(T::Boolean) }
    def self.supports_cte_materialization_specifiers?; end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@return_ — whether the lock was acquired.
    sig { returns(T::Boolean) }
    def advisory_lock; end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@return_ — whether the lock was released.
    sig { returns(T::Boolean) }
    def advisory_unlock; end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@return_ — +true+
    sig { returns(T::Boolean) }
    def advisory_lock!; end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { returns(Object) }
    def with_advisory_lock; end

    # Tests whether this record has an advisory lock on it.
    sig { returns(T::Boolean) }
    def advisory_locked?; end

    # Tests whether this record is locked by the current database session.
    sig { returns(T::Boolean) }
    def owns_advisory_lock?; end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    sig { void }
    def advisory_unlock!; end

    # _@param_ `query`
    sig { params(query: String).returns(T::Boolean) }
    def pg_or_jdbc_query(query); end

    # Whether an advisory lock should be acquired in the same transaction
    # that created the record.
    # 
    # This helps prevent another thread or database session from acquiring a
    # lock on the record between the time you create it and the time you
    # request a lock, since other sessions will not be able to see the new
    # record until the transaction that creates it is completed (at which
    # point you have already acquired the lock).
    # 
    # ```ruby
    # record = MyLockableRecord.create(create_with_advisory_lock: true)
    # record.advisory_locked?
    # => true
    # ```
    sig { returns(T::Boolean) }
    attr_accessor :create_with_advisory_lock
  end

  # 
  # Notifiers hook into Postgres LISTEN/NOTIFY functionality to emit and listen for notifications across processes.
  # 
  # Notifiers can emit NOTIFY messages through Postgres.
  # A notifier will LISTEN for messages by creating a background thread that runs in an instance of +Concurrent::ThreadPoolExecutor+.
  # When a message is received, the notifier passes the message to each of its recipients.
  class Notifier
    AdapterCannotListenError = T.let(Class.new(StandardError), T.untyped)
    CHANNEL = T.let('good_job'.freeze, T.untyped)
    EXECUTOR_OPTIONS = T.let({
  name: name,
  min_threads: 0,
  max_threads: 1,
  auto_terminate: true,
  idletime: 60,
  max_queue: 1,
  fallback_policy: :discard,
}.freeze, T.untyped)
    WAIT_INTERVAL = T.let(1, T.untyped)

    class << self
      # List of all instantiated Notifiers in the current process.
      sig { returns(T::Array[GoodJob::Adapter]) }
      attr_reader :instances
    end

    # sord duck - #to_json looks like a duck type, replacing with untyped
    # sord omit - no YARD return type given, using untyped
    # Send a message via Postgres NOTIFY
    # 
    # _@param_ `message`
    sig { params(message: T.untyped).returns(T.untyped) }
    def self.notify(message); end

    # sord duck - #call looks like a duck type, replacing with untyped
    # _@param_ `recipients`
    sig { params(recipients: T::Array[T.any(T.untyped, [Object, Symbol])]).void }
    def initialize(*recipients); end

    # Tests whether the notifier is active and listening for new messages.
    sig { returns(T.nilable(T::Boolean)) }
    def listening?; end

    # Tests whether the notifier is running.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Tests whether the scheduler is shutdown.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # Shut down the notifier.
    # This stops the background LISTENing thread.
    # Use {#shutdown?} to determine whether threads have stopped.
    # 
    # _@param_ `timeout` — Seconds to wait for active threads.  * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1)); end

    # Restart the notifier.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1)); end

    # sord omit - no YARD type given for "_time", using untyped
    # sord omit - no YARD type given for "_result", using untyped
    # sord omit - no YARD type given for "thread_error", using untyped
    # Invoked on completion of ThreadPoolExecutor task
    sig { params(_time: T.untyped, _result: T.untyped, thread_error: T.untyped).void }
    def listen_observer(_time, _result, thread_error); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def create_executor; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def listen; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def with_listen_connection; end

    # sord duck - #call looks like a duck type, replacing with untyped
    # List of recipients that will receive notifications.
    sig { returns(T::Array[T.any(T.untyped, [Object, Symbol])]) }
    attr_reader :recipients

    # sord omit - no YARD type given for :executor, using untyped
    # Returns the value of attribute executor.
    sig { returns(T.untyped) }
    attr_reader :executor
  end

  # 
  # Schedulers are generic thread pools that are responsible for
  # periodically checking for available tasks, executing tasks within a thread,
  # and efficiently scaling active threads.
  # 
  # Every scheduler has a single {JobPerformer} that will execute tasks.
  # The scheduler is responsible for calling its performer efficiently across threads managed by an instance of +Concurrent::ThreadPoolExecutor+.
  # If a performer does not have work, the thread will go to sleep.
  # The scheduler maintains an instance of +Concurrent::TimerTask+, which wakes sleeping threads and causes them to check whether the performer has new work.
  class Scheduler
    DEFAULT_EXECUTOR_OPTIONS = T.let({
  name: name,
  min_threads: 0,
  max_threads: Configuration::DEFAULT_MAX_THREADS,
  auto_terminate: true,
  idletime: 60,
  max_queue: Configuration::DEFAULT_MAX_THREADS,
  fallback_policy: :discard,
}.freeze, T.untyped)

    class << self
      # List of all instantiated Schedulers in the current process.
      sig { returns(T::Array[GoodJob::Scheduler]) }
      attr_reader :instances
    end

    # Creates GoodJob::Scheduler(s) and Performers from a GoodJob::Configuration instance.
    # 
    # _@param_ `configuration`
    # 
    # _@param_ `warm_cache_on_initialize`
    sig { params(configuration: GoodJob::Configuration, warm_cache_on_initialize: T::Boolean).returns(T.any(GoodJob::Scheduler, GoodJob::MultiScheduler)) }
    def self.from_configuration(configuration, warm_cache_on_initialize: true); end

    # _@param_ `performer`
    # 
    # _@param_ `max_threads` — number of seconds between polls for jobs
    # 
    # _@param_ `max_cache` — maximum number of scheduled jobs to cache in memory
    # 
    # _@param_ `warm_cache_on_initialize` — whether to warm the cache immediately
    sig do
      params(
        performer: GoodJob::JobPerformer,
        max_threads: T.nilable(Numeric),
        max_cache: T.nilable(Numeric),
        warm_cache_on_initialize: T::Boolean
      ).void
    end
    def initialize(performer, max_threads: nil, max_cache: nil, warm_cache_on_initialize: true); end

    # Tests whether the scheduler is running.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Tests whether the scheduler is shutdown.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # Shut down the scheduler.
    # This stops all threads in the thread pool.
    # Use {#shutdown?} to determine whether threads have stopped.
    # 
    # _@param_ `timeout` — Seconds to wait for actively executing jobs to finish  * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any active tasks. * A positive number will wait that many seconds before stopping any remaining active tasks.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1)); end

    # Restart the Scheduler.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait for actively executing jobs to finish; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1)); end

    # Wakes a thread to allow the performer to execute a task.
    # 
    # _@param_ `state` — Contextual information for the performer. See {JobPerformer#next?}.
    # 
    # _@return_ — Whether work was started.
    # 
    # * +nil+ if the scheduler is unable to take new work, for example if the thread pool is shut down or at capacity.
    # * +true+ if the performer started executing work.
    # * +false+ if the performer decides not to attempt to execute a task based on the +state+ that is passed to it.
    sig { params(state: T.nilable(Object)).void }
    def create_thread(state = nil); end

    # sord omit - no YARD type given for "time", using untyped
    # sord omit - no YARD type given for "output", using untyped
    # sord omit - no YARD type given for "thread_error", using untyped
    # Invoked on completion of ThreadPoolExecutor task
    sig { params(time: T.untyped, output: T.untyped, thread_error: T.untyped).void }
    def task_observer(time, output, thread_error); end

    # Information about the Scheduler
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def stats; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def warm_cache; end

    sig { void }
    def create_executor; end

    # _@param_ `delay`
    sig { params(delay: Integer).void }
    def create_task(delay = 0); end

    # _@param_ `name`
    # 
    # _@param_ `payload`
    sig { params(name: String, payload: T::Hash[T.untyped, T.untyped], block: T.untyped).void }
    def instrument(name, payload = {}, &block); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def cache_count; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def remaining_cache_count; end

    # sord omit - no YARD type given for :performer, using untyped
    # Returns the value of attribute performer.
    sig { returns(T.untyped) }
    attr_reader :performer

    # sord omit - no YARD type given for :executor, using untyped
    # Returns the value of attribute executor.
    sig { returns(T.untyped) }
    attr_reader :executor

    # sord omit - no YARD type given for :timer_set, using untyped
    # Returns the value of attribute timer_set.
    sig { returns(T.untyped) }
    attr_reader :timer_set

    # Custom sub-class of +Concurrent::ThreadPoolExecutor+ to add additional worker status.
    # @private
    class ThreadPoolExecutor < Concurrent::ThreadPoolExecutor
      # Number of inactive threads available to execute tasks.
      # https://github.com/ruby-concurrency/concurrent-ruby/issues/684#issuecomment-427594437
      sig { returns(Integer) }
      def ready_worker_count; end
    end

    # Custom sub-class of +Concurrent::TimerSet+ for additional behavior.
    # @private
    class TimerSet < Concurrent::TimerSet
      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def length; end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def reset; end
    end
  end

  # 
  # +GoodJob::Configuration+ provides normalized configuration information to
  # the rest of GoodJob. It combines environment information with explicitly
  # set options to get the final values for each option.
  class Configuration
    EXECUTION_MODES = T.let([:async, :async_server, :external, :inline].freeze, T.untyped)
    DEFAULT_MAX_THREADS = T.let(5, T.untyped)
    DEFAULT_POLL_INTERVAL = T.let(10, T.untyped)
    DEFAULT_MAX_CACHE = T.let(10000, T.untyped)
    DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO = T.let(24 * 60 * 60, T.untyped)
    DEFAULT_SHUTDOWN_TIMEOUT = T.let(-1, T.untyped)

    # _@param_ `options` — Any explicitly specified configuration options to use. Keys are symbols that match the various methods on this class.
    # 
    # _@param_ `env` — A +Hash+ from which to read environment variables that might specify additional configuration values.
    sig { params(options: T::Hash[T.untyped, T.untyped], env: T::Hash[T.untyped, T.untyped]).void }
    def initialize(options, env: ENV); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def validate!; end

    # Specifies how and where jobs should be executed. See {Adapter#initialize}
    # for more details on possible values.
    sig { returns(Symbol) }
    def execution_mode; end

    # Indicates the number of threads to use per {Scheduler}. Note that
    # {#queue_string} may provide more specific thread counts to use with
    # individual schedulers.
    sig { returns(Integer) }
    def max_threads; end

    # Describes which queues to execute jobs from and how those queues should
    # be grouped into {Scheduler} instances. See
    # {file:README.md#optimize-queues-threads-and-processes} for more details
    # on the format of this string.
    sig { returns(String) }
    def queue_string; end

    # The number of seconds between polls for jobs. GoodJob will execute jobs
    # on queues continuously until a queue is empty, at which point it will
    # poll (using this interval) for new queued jobs to execute.
    sig { returns(Integer) }
    def poll_interval; end

    # The maximum number of future-scheduled jobs to store in memory.
    # Storing future-scheduled jobs in memory reduces execution latency
    # at the cost of increased memory usage. 10,000 stored jobs = ~20MB.
    sig { returns(Integer) }
    def max_cache; end

    # The number of seconds to wait for jobs to finish when shutting down
    # before stopping the thread. +-1+ is forever.
    sig { returns(Numeric) }
    def shutdown_timeout; end

    # Number of seconds to preserve jobs when using the +good_job cleanup_preserved_jobs+ CLI command.
    # This configuration is only used when {GoodJob.preserve_job_records} is +true+.
    sig { returns(Integer) }
    def cleanup_preserved_jobs_before_seconds_ago; end

    # Tests whether to daemonize the process.
    sig { returns(T::Boolean) }
    def daemonize?; end

    # Path of the pidfile to create when running as a daemon.
    sig { returns(T.any(Pathname, String)) }
    def pidfile; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def rails_config; end

    # The options that were explicitly set when initializing +Configuration+.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :options

    # The environment from which to read GoodJob's environment variables. By
    # default, this is the current process's environment, but it can be set
    # to something else in {#initialize}.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :env
  end

  # 
  # JobPerformer queries the database for jobs and performs them on behalf of a
  # {Scheduler}. It mainly functions as glue between a {Scheduler} and the jobs
  # it should be executing.
  # 
  # The JobPerformer must be safe to execute across multiple threads.
  class JobPerformer
    # _@param_ `queue_string` — Queues to execute jobs from
    sig { params(queue_string: String).void }
    def initialize(queue_string); end

    # A meaningful name to identify the performer in logs and for debugging.
    # 
    # _@return_ — The queues from which Jobs are worked
    sig { returns(String) }
    def name; end

    # Perform the next eligible job
    # 
    # _@return_ — Returns job result or +nil+ if no job was found
    sig { void }
    def next; end

    # sord omit - no YARD type given for "state", using untyped
    # Tests whether this performer should be used in GoodJob's current state.
    # 
    # For example, state will be a LISTEN/NOTIFY message that is passed down
    # from the Notifier to the Scheduler. The Scheduler is able to ask
    # its performer "does this message relate to you?", and if not, ignore it
    # to minimize thread wake-ups, database queries, and thundering herds.
    # 
    # _@return_ — whether the performer's {#next} method should be
    # called in the current state.
    sig { params(state: T.untyped).returns(T::Boolean) }
    def next?(state = {}); end

    # The Returns timestamps of when next tasks may be available.
    # 
    # _@param_ `after` — future jobs scheduled after this time
    # 
    # _@param_ `limit` — number of future timestamps to return
    # 
    # _@param_ `now_limit` — number of past timestamps to return
    sig { params(after: T.nilable(T.any(DateTime, Time)), limit: T.nilable(Integer), now_limit: T.nilable(Integer)).returns(T.nilable(T::Array[[Time, DateTime]])) }
    def next_at(after: nil, limit: nil, now_limit: nil); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def job_query; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def parsed_queues; end

    # sord omit - no YARD type given for :queue_string, using untyped
    # Returns the value of attribute queue_string.
    sig { returns(T.untyped) }
    attr_reader :queue_string
  end

  # 
  # Listens to GoodJob notifications and logs them.
  # 
  # Each method corresponds to the name of a notification. For example, when
  # the {Scheduler} shuts down, it sends a notification named
  # +"scheduler_shutdown.good_job"+ and the {#scheduler_shutdown} method will
  # be called here. See the
  # {https://api.rubyonrails.org/classes/ActiveSupport/LogSubscriber.html ActiveSupport::LogSubscriber}
  # documentation for more.
  class LogSubscriber < ActiveSupport::LogSubscriber
    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def create(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def finished_timer_task(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def finished_job_task(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def scheduler_create_pool(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def scheduler_shutdown_start(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def scheduler_shutdown(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def scheduler_restart_pools(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def perform_job(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def notifier_listen(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def notifier_notified(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def notifier_notify_error(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def notifier_unlisten(event); end

    # sord warn - ActiveSupport::Notifications::Event wasn't able to be resolved to a constant in this project
    # Responds to the +.good_job+ notification.
    # 
    # _@param_ `event`
    sig { params(event: ActiveSupport::Notifications::Event).void }
    def cleanup_preserved_jobs(event); end

    # Get the logger associated with this {LogSubscriber} instance.
    sig { returns(Logger) }
    def logger; end

    # Tracks all loggers that {LogSubscriber} is writing to. You can write to
    # multiple logs by appending to this array. After updating it, you should
    # usually call {LogSubscriber.reset_logger} to make sure they are all
    # written to.
    # 
    # Defaults to {GoodJob.logger}.
    # 
    # Write to STDOUT and to a file:
    # ```ruby
    # GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
    # GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
    # GoodJob::LogSubscriber.reset_logger
    # ```
    sig { returns(T::Array[Logger]) }
    def self.loggers; end

    # Represents all the loggers attached to {LogSubscriber} with a single
    # logging interface. Writing to this logger is a shortcut for writing to
    # each of the loggers in {LogSubscriber.loggers}.
    sig { returns(Logger) }
    def self.logger; end

    # Reset {LogSubscriber.logger} and force it to rebuild a new shortcut to
    # all the loggers in {LogSubscriber.loggers}. You should usually call
    # this after modifying the {LogSubscriber.loggers} array.
    sig { void }
    def self.reset_logger; end

    # sord omit - no YARD type given for "*tags", using untyped
    # Add "GoodJob" plus any specified tags to every
    # {ActiveSupport::TaggedLogging} logger in {LogSubscriber.loggers}. Tags
    # are only applicable inside the block passed to this method.
    sig { params(tags: T.untyped, block: T.untyped).void }
    def tag_logger(*tags, &block); end
  end

  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # sord omit - no YARD type given for "schedulers", using untyped
    sig { params(schedulers: T.untyped).void }
    def initialize(schedulers); end

    # Delegates to {Scheduler#running?}.
    sig { returns(T::Boolean) }
    def running?; end

    # Delegates to {Scheduler#shutdown?}.
    sig { returns(T::Boolean) }
    def shutdown?; end

    # sord omit - no YARD type given for "timeout:", using untyped
    # sord omit - no YARD return type given, using untyped
    # Delegates to {Scheduler#shutdown}.
    sig { params(timeout: T.untyped).returns(T.untyped) }
    def shutdown(timeout: -1)); end

    # sord omit - no YARD type given for "timeout:", using untyped
    # sord omit - no YARD return type given, using untyped
    # Delegates to {Scheduler#restart}.
    sig { params(timeout: T.untyped).returns(T.untyped) }
    def restart(timeout: -1)); end

    # sord omit - no YARD type given for "state", using untyped
    # sord omit - no YARD return type given, using untyped
    # Delegates to {Scheduler#create_thread}.
    sig { params(state: T.untyped).returns(T.untyped) }
    def create_thread(state = nil); end

    # _@return_ — List of the scheduler delegates
    sig { returns(T::Array[Scheduler]) }
    attr_reader :schedulers
  end

  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentExecution
    class << self
      # Error captured by retry_on
      sig { returns(T.nilable(Exception)) }
      attr_accessor :error_on_retry

      # Error captured by discard_on
      sig { returns(T.nilable(Exception)) }
      attr_accessor :error_on_discard
    end

    # Resets attributes
    sig { void }
    def self.reset; end

    # _@return_ — Current process ID
    sig { returns(Integer) }
    def self.process_id; end

    # _@return_ — Current thread name
    sig { returns(String) }
    def self.thread_name; end
  end

  # 
  # Implements the Rails generator used for setting up GoodJob in a Rails
  # application. Run it with +bin/rails g good_job:install+ in your console.
  # 
  # This generator is primarily dedicated to stubbing out a migration that adds
  # a table to hold GoodJob's queued jobs in your database.
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    # sord omit - no YARD return type given, using untyped
    # Generates the actual migration file and places it on disk.
    sig { returns(T.untyped) }
    def create_migration_file; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def migration_version; end
  end
end

# typed: true
module ActiveJob
  # :nodoc:
  module QueueAdapters
    # See {GoodJob::Adapter} for details.
    class GoodJobAdapter < GoodJob::Adapter
      EXECUTION_MODES = T.let([:async, :async_server, :external, :inline].freeze, T.untyped)
    end
  end
end
