# typed: strong
# typed: false
# frozen_string_literal: true
module GoodJob
  include GoodJob::Dependencies
  DEFAULT_LOGGER = T.let(ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout)), T.untyped)
  VERSION = T.let('2.16.1', T.untyped)

  class << self
    # sord warn - ActiveRecord::Base wasn't able to be resolved to a constant in this project
    # sord warn - ActiveRecord::Base wasn't able to be resolved to a constant in this project
    # The ActiveRecord parent class inherited by +GoodJob::Execution+ (default: +ActiveRecord::Base+).
    # Use this when using multiple databases or other custom ActiveRecord configuration.
    # 
    # Change the base class:
    # ```ruby
    # GoodJob.active_record_parent_class = "CustomApplicationRecord"
    # ```
    sig { returns(ActiveRecord::Base) }
    attr_accessor :active_record_parent_class

    # The logger used by GoodJob (default: +Rails.logger+).
    # Use this to redirect logs to a special location or file.
    # 
    # Output GoodJob logs to a file:
    # ```ruby
    # GoodJob.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
    # ```
    sig { returns(T.nilable(Logger)) }
    attr_accessor :logger

    # Whether to preserve job records in the database after they have finished (default: +false+).
    # By default, GoodJob destroys job records after the job is completed successfully.
    # If you want to preserve jobs for latter inspection, set this to +true+.
    # If you want to preserve only jobs that finished with error for latter inspection, set this to +:on_unhandled_error+.
    # If +true+, you will need to clean out jobs using the +good_job cleanup_preserved_jobs+ CLI command or
    # by using +Goodjob.cleanup_preserved_jobs+.
    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :preserve_job_records

    # Whether to re-perform a job when a type of +StandardError+ is raised to GoodJob (default: +true+).
    # If +true+, causes jobs to be re-queued and retried if they raise an instance of +StandardError+.
    # If +false+, jobs will be discarded or marked as finished if they raise an instance of +StandardError+.
    # Instances of +Exception+, like +SIGINT+, will *always* be retried, regardless of this attribute's value.
    sig { returns(T.nilable(T::Boolean)) }
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

  # Called with exception when a GoodJob thread raises an exception
  # 
  # _@param_ `exception` — Exception that was raised
  sig { params(exception: Exception).void }
  def self._on_thread_error(exception); end

  # Stop executing jobs.
  # GoodJob does its work in pools of background threads.
  # When forking processes you should shut down these background threads before forking, and restart them after forking.
  # For example, you should use +shutdown+ and +restart+ when using async execution mode with Puma.
  # See the {file:README.md#executing-jobs-async--in-process} for more explanation and examples.
  # 
  # _@param_ `timeout` — Seconds to wait for actively executing jobs to finish * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any active tasks. * +1..+, the scheduler will wait that many seconds before stopping any remaining active tasks.
  # 
  # _@param_ `wait` — whether to wait for shutdown
  sig { params(timeout: T.nilable(Numeric)).void }
  def self.shutdown(timeout: -1); end

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
  def self.restart(timeout: -1); end

  # Sends +#shutdown+ or +#restart+ to executable objects ({GoodJob::Notifier}, {GoodJob::Poller}, {GoodJob::Scheduler}, {GoodJob::MultiScheduler}, {GoodJob::CronManager})
  # 
  # _@param_ `executables` — Objects to shut down.
  # 
  # _@param_ `method_name` — Method to call, e.g. +:shutdown+ or +:restart+.
  # 
  # _@param_ `timeout`
  sig { params(executables: T::Array[T.any(Notifier, Poller, Scheduler, MultiScheduler, CronManager)], method_name: Symbol, timeout: T.nilable(Numeric)).void }
  def self._shutdown_all(executables, method_name = :shutdown, timeout: -1); end

  # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
  # Destroys preserved job records.
  # By default, GoodJob destroys job records when the job is performed and this
  # method is not necessary. However, when `GoodJob.preserve_job_records = true`,
  # the jobs will be preserved in the database. This is useful when wanting to
  # analyze or inspect job performance.
  # If you are preserving job records this way, use this method regularly to
  # destroy old records and preserve space in your database.
  # 
  # _@param_ `older_than` — Jobs older than this will be destroyed (default: +86400+).
  # 
  # _@return_ — Number of jobs that were destroyed.
  sig { params(older_than: T.nilable(T.any(Numeric, ActiveSupport::Duration))).returns(Integer) }
  def self.cleanup_preserved_jobs(older_than: nil); end

  # Perform all queued jobs in the current thread.
  # This is primarily intended for usage in a test environment.
  # Unhandled job errors will be raised.
  # 
  # _@param_ `queue_string` — Queues to execute jobs from
  sig { params(queue_string: String).void }
  def self.perform_inline(queue_string = "*"); end

  # sord omit - no YARD return type given, using untyped
  sig { returns(T.untyped) }
  def self._executables; end

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

    class << self
      # Whether the CLI is running from the executable
      sig { returns(T.nilable(T::Boolean)) }
      attr_accessor :within_exe

      # Whether to log to STDOUT
      sig { returns(T.nilable(T::Boolean)) }
      attr_accessor :log_to_stdout
    end

    sig { returns(T::Boolean) }
    def self.exit_on_failure?; end

    sig { void }
    def start; end

    # The +good_job + command.
    sig { void }
    def cleanup_preserved_jobs; end
  end

  # @deprecated Use {GoodJob::Execution} instead.
  class Job < GoodJob::Execution
    PreviouslyPerformedError = T.let(Class.new(StandardError), T.untyped)
    ERROR_MESSAGE_SEPARATOR = T.let(": ", T.untyped)
    DEFAULT_QUEUE_NAME = T.let('default', T.untyped)
    DEFAULT_PRIORITY = T.let(0, T.untyped)
    RecordAlreadyAdvisoryLockedError = T.let(Class.new(StandardError), T.untyped)
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
  run_now: true,
}.freeze, T.untyped)

    class << self
      # List of all instantiated Pollers in the current process.
      sig { returns(T.nilable(T::Array[GoodJob::Poller])) }
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
    sig { params(recipients: T::Array[T.any(Proc, T.untyped, [Object, Symbol])], poll_interval: T.nilable(Integer)).void }
    def initialize(*recipients, poll_interval: nil); end

    # Tests whether the timer is running.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Tests whether the timer is shutdown.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # Shut down the poller.
    # Use {#shutdown?} to determine whether threads have stopped.
    # 
    # _@param_ `timeout` — Seconds to wait for active threads. * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1); end

    # Restart the poller.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1); end

    # Invoked on completion of TimerTask task.
    # 
    # _@param_ `time`
    # 
    # _@param_ `executed_task`
    # 
    # _@param_ `thread_error`
    sig { params(time: Integer, executed_task: T.nilable(Object), thread_error: T.nilable(Exception)).void }
    def timer_observer(time, executed_task, thread_error); end

    sig { void }
    def create_timer; end

    # sord duck - #call looks like a duck type, replacing with untyped
    # List of recipients that will receive notifications.
    sig { returns(T::Array[T.any(T.untyped, [Object, Symbol])]) }
    attr_reader :recipients

    # sord warn - Concurrent::TimerTask wasn't able to be resolved to a constant in this project
    sig { returns(T.nilable(Concurrent::TimerTask)) }
    attr_reader :timer
  end

  # 
  # ActiveJob Adapter.
  class Adapter
    class << self
      # List of all instantiated Adapters in the current process.
      sig { returns(T.nilable(T::Array[GoodJob::Adapter])) }
      attr_reader :instances
    end

    # _@param_ `execution_mode` — specifies how and where jobs should be executed. You can also set this with the environment variable +GOOD_JOB_EXECUTION_MODE+.  - +:inline+ executes jobs immediately in whatever process queued them (usually the web server process). This should only be used in test and development environments. - +:external+ causes the adapter to enqueue jobs, but not execute them. When using this option (the default for production environments), you'll need to use the command-line tool to actually execute your jobs. - +:async+ (or +:async_server+) executes jobs in separate threads within the Rails web server process (`bundle exec rails server`). It can be more economical for small workloads because you don't need a separate machine or environment for running your jobs, but if your web server is under heavy load or your jobs require a lot of resources, you should choose +:external+ instead.   When not in the Rails web server, jobs will execute in +:external+ mode to ensure jobs are not executed within `rails console`, `rails db:migrate`, `rails assets:prepare`, etc. - +:async_all+ executes jobs in any Rails process.  The default value depends on the Rails environment:  - +development+ and +test+: +:inline+ - +production+ and all other environments: +:external+
    # 
    # _@param_ `max_threads` — sets the number of threads per scheduler to use when +execution_mode+ is set to +:async+. The +queues+ parameter can specify a number of threads for each group of queues which will override this value. You can also set this with the environment variable +GOOD_JOB_MAX_THREADS+. Defaults to +5+.
    # 
    # _@param_ `queues` — determines which queues to execute jobs from when +execution_mode+ is set to +:async+. See {file:README.md#optimize-queues-threads-and-processes} for more details on the format of this string. You can also set this with the environment variable +GOOD_JOB_QUEUES+. Defaults to +"*"+.
    # 
    # _@param_ `poll_interval` — sets the number of seconds between polls for jobs when +execution_mode+ is set to +:async+. You can also set this with the environment variable +GOOD_JOB_POLL_INTERVAL+. Defaults to +1+.
    # 
    # _@param_ `start_async_on_initialize` — whether to start the async scheduler when the adapter is initialized.
    sig do
      params(
        execution_mode: T.nilable(Symbol),
        queues: T.nilable(String),
        max_threads: T.nilable(Integer),
        poll_interval: T.nilable(Integer),
        start_async_on_initialize: T.nilable(T::Boolean)
      ).void
    end
    def initialize(execution_mode: nil, queues: nil, max_threads: nil, poll_interval: nil, start_async_on_initialize: nil); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Enqueues the ActiveJob job to be performed.
    # For use by Rails; you should generally not call this directly.
    # 
    # _@param_ `active_job` — the job to be enqueued from +#perform_later+
    sig { params(active_job: ActiveJob::Base).returns(GoodJob::Execution) }
    def enqueue(active_job); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Enqueues an ActiveJob job to be run at a specific time.
    # For use by Rails; you should generally not call this directly.
    # 
    # _@param_ `active_job` — the job to be enqueued from +#perform_later+
    # 
    # _@param_ `timestamp` — the epoch time to perform the job
    sig { params(active_job: ActiveJob::Base, timestamp: T.nilable(Integer)).returns(GoodJob::Execution) }
    def enqueue_at(active_job, timestamp); end

    # Shut down the thread pool executors.
    # 
    # _@param_ `timeout` — Seconds to wait for active threads. * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    sig { params(timeout: T.nilable(T.any(Numeric, Symbol))).void }
    def shutdown(timeout: :default); end

    # Whether in +:async+ execution mode.
    sig { returns(T::Boolean) }
    def execute_async?; end

    # Whether in +:external+ execution mode.
    sig { returns(T::Boolean) }
    def execute_externally?; end

    # Whether in +:inline+ execution mode.
    sig { returns(T::Boolean) }
    def execute_inline?; end

    # Start async executors
    sig { void }
    def start_async; end

    # Whether the async executors are running
    sig { returns(T::Boolean) }
    def async_started?; end

    # Whether running in a web server process.
    sig { returns(T.nilable(T::Boolean)) }
    def in_server_process?; end
  end

  # ActiveRecord model that represents an GoodJob process (either async or CLI).
  class Process < GoodJob::BaseRecord
    include GoodJob::AssignableConnection
    include GoodJob::Lockable

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Processes that are inactive and unlocked (e.g. SIGKILLed)
    sig { returns(ActiveRecord::Relation) }
    def self.active; end

    # Whether the +good_job_processes+ table exsists.
    sig { returns(T::Boolean) }
    def self.migrated?; end

    # UUID that is unique to the current process and changes when forked.
    sig { returns(String) }
    def self.current_id; end

    # Hash representing metadata about the current process.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def self.current_state; end

    # sord omit - no YARD return type given, using untyped
    # Deletes all inactive process records.
    sig { returns(T.untyped) }
    def self.cleanup; end

    # Registers the current process in the database
    sig { returns(GoodJob::Process) }
    def self.register; end

    # sord omit - no YARD return type given, using untyped
    # Unregisters the instance.
    sig { returns(T.untyped) }
    def deregister; end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@param_ `key` — Key to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was acquired.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was released.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — +true+
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function); end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(Object) }
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Tests whether this record has an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_locked?(key: lockable_key); end

    # Tests whether this record does not have an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlocked?(key: lockable_key); end

    # Tests whether this record is locked by the current database session.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def owns_advisory_lock?(key: lockable_key); end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).void }
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Default Advisory Lock key
    sig { returns(String) }
    def lockable_key; end

    # sord omit - no YARD type given for "column:", using untyped
    # Default Advisory Lock key for column-based locking
    sig { params(column: T.untyped).returns(String) }
    def lockable_column_key(column: self.class._advisory_lockable_column); end
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
    # _@param_ `column` — column values to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — A relation selecting only the records that were locked.
    sig { params(column: T.any(String, Symbol), function: T.any(String, Symbol)).returns(ActiveRecord::Relation) }
    def self.advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Joins the current query with Postgres's +pg_locks+ table AND SELECTs the resulting columns
    # 
    # _@param_ `column` — column values to Advisory Lock against
    sig { params(column: T.any(String, Symbol)).returns(ActiveRecord::Relation) }
    def self.joins_advisory_locks(column: _advisory_lockable_column); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Find records that do not have an advisory lock on them.
    # 
    # _@param_ `column` — column values to Advisory Lock against
    sig { params(column: T.any(String, Symbol)).returns(ActiveRecord::Relation) }
    def self.advisory_unlocked(column: _advisory_lockable_column); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Find records with advisory locks owned by the current Postgres
    # session/connection.
    # 
    # _@param_ `column` — column values to Advisory Lock against
    sig { params(column: T.any(String, Symbol)).returns(ActiveRecord::Relation) }
    def self.advisory_locked(column: _advisory_lockable_column); end

    # Acquires an advisory lock on the selected record(s) and safely releases
    # it after the passed block is completed. The block will be passed an
    # array of the locked records as its first argument.
    # 
    # Note that this will not block and wait for locks to be acquired.
    # Instead, it will acquire a lock on all the selected records that it
    # can (as in {Lockable.advisory_lock}) and only pass those that could be
    # locked to the block.
    # 
    # _@param_ `column` — name of advisory lock or unlock function
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@param_ `unlock_session` — Whether to unlock all advisory locks in the session afterwards
    # 
    # _@return_ — the result of the block.
    # 
    # Work on the first two +MyLockableRecord+ objects that could be locked:
    # ```ruby
    # MyLockableRecord.order(created_at: :asc).limit(2).with_advisory_lock do |record|
    #   do_something_with record
    # end
    # ```
    sig { params(column: T.any(String, Symbol), function: T.any(String, Symbol), unlock_session: T::Boolean).returns(Object) }
    def self.with_advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function, unlock_session: false); end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock_key} to release all remaining locks.
    # 
    # _@param_ `key` — Key to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was acquired.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def self.advisory_lock_key(key, function: advisory_lockable_function); end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was released.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def self.advisory_unlock_key(key, function: advisory_unlockable_function); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def self._advisory_lockable_column; end

    sig { returns(T::Boolean) }
    def self.supports_cte_materialization_specifiers?; end

    # Postgres advisory unlocking function for the class
    # 
    # _@param_ `function` — name of advisory lock or unlock function
    sig { params(function: T.any(String, Symbol)).returns(T::Boolean) }
    def self.advisory_unlockable_function(function = advisory_lockable_function); end

    # Unlocks all advisory locks active in the current database session/connection
    sig { void }
    def self.advisory_unlock_session; end

    # Converts SQL query strings between PG-compatible and JDBC-compatible syntax
    # 
    # _@param_ `query`
    sig { params(query: String).returns(T::Boolean) }
    def self.pg_or_jdbc_query(query); end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@param_ `key` — Key to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was acquired.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was released.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — +true+
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function); end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(Object) }
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Tests whether this record has an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_locked?(key: lockable_key); end

    # Tests whether this record does not have an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlocked?(key: lockable_key); end

    # Tests whether this record is locked by the current database session.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def owns_advisory_lock?(key: lockable_key); end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).void }
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Default Advisory Lock key
    sig { returns(String) }
    def lockable_key; end

    # sord omit - no YARD type given for "column:", using untyped
    # Default Advisory Lock key for column-based locking
    sig { params(column: T.untyped).returns(String) }
    def lockable_column_key(column: self.class._advisory_lockable_column); end

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

  # :nodoc:
  class Notifier
    include ActiveSupport::Callbacks
    include GoodJob::Notifier::ProcessRegistration
    CHANNEL = T.let('good_job', T.untyped)
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
    RECONNECT_INTERVAL = T.let(5, T.untyped)
    CONNECTION_ERRORS = T.let(%w[
  ActiveRecord::ConnectionNotEstablished
  ActiveRecord::StatementInvalid
  PG::UnableToSend
  PG::Error
].freeze, T.untyped)

    class << self
      # List of all instantiated Notifiers in the current process.
      sig { returns(T.nilable(T::Array[GoodJob::Notifier])) }
      attr_reader :instances

      # sord warn - ActiveRecord::ConnectionAdapters::AbstractAdapter wasn't able to be resolved to a constant in this project
      # sord warn - ActiveRecord::ConnectionAdapters::AbstractAdapter wasn't able to be resolved to a constant in this project
      # ActiveRecord Connection that has been established for the Notifier.
      sig { returns(T.nilable(ActiveRecord::ConnectionAdapters::AbstractAdapter)) }
      attr_accessor :connection
    end

    # sord duck - #to_json looks like a duck type, replacing with untyped
    # Send a message via Postgres NOTIFY
    # 
    # _@param_ `message`
    sig { params(message: T.untyped).void }
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
    # _@param_ `timeout` — Seconds to wait for active threads. * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any threads. * A positive number will wait that many seconds before stopping any remaining active threads.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1); end

    # Restart the notifier.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1); end

    # Invoked on completion of ThreadPoolExecutor task
    # 
    # _@param_ `_time`
    # 
    # _@param_ `_result`
    # 
    # _@param_ `thread_error`
    sig { params(_time: Integer, _result: Object, thread_error: T.nilable(Exception)).void }
    def listen_observer(_time, _result, thread_error); end

    sig { void }
    def create_executor; end

    # sord omit - no YARD type given for "delay:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(delay: T.untyped).returns(T.untyped) }
    def listen(delay: 0); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def with_connection; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def wait_for_notify; end

    # sord omit - no YARD return type given, using untyped
    # Registers the current process.
    sig { returns(T.untyped) }
    def register_process; end

    # sord omit - no YARD return type given, using untyped
    # Deregisters the current process.
    sig { returns(T.untyped) }
    def deregister_process; end

    # sord duck - #call looks like a duck type, replacing with untyped
    # List of recipients that will receive notifications.
    sig { returns(T::Array[T.any(T.untyped, [Object, Symbol])]) }
    attr_reader :recipients

    # sord warn - Concurrent::ThreadPoolExecutor wasn't able to be resolved to a constant in this project
    sig { returns(Concurrent::ThreadPoolExecutor) }
    attr_reader :executor

    # Extends the Notifier to register the process in the database.
    module ProcessRegistration
      extend ActiveSupport::Concern

      # sord omit - no YARD return type given, using untyped
      # Registers the current process.
      sig { returns(T.untyped) }
      def register_process; end

      # sord omit - no YARD return type given, using untyped
      # Deregisters the current process.
      sig { returns(T.untyped) }
      def deregister_process; end
    end
  end

  # ActiveRecord model that represents an +ActiveJob+ job.
  class Execution < GoodJob::BaseRecord
    include GoodJob::Lockable
    include GoodJob::Filterable
    PreviouslyPerformedError = T.let(Class.new(StandardError), T.untyped)
    ERROR_MESSAGE_SEPARATOR = T.let(": ", T.untyped)
    DEFAULT_QUEUE_NAME = T.let('default', T.untyped)
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
    # GoodJob::Execution.queue_parser('-queue1,queue2')
    # => { exclude: [ 'queue1', 'queue2' ] }
    # ```
    sig { params(string: String).returns(T::Hash[T.untyped, T.untyped]) }
    def self.queue_parser(string); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs with given ActiveJob ID
    # 
    # _@param_ `active_job_id` — ActiveJob ID
    sig { params(active_job_id: String).returns(ActiveRecord::Relation) }
    def self.active_job_id(active_job_id); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs with given class name
    # 
    # _@param_ `job_class` — Execution class name
    sig { params(job_class: String).returns(ActiveRecord::Relation) }
    def self.job_class(job_class); end

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
    # Order jobs by scheduled or created (oldest first).
    sig { returns(ActiveRecord::Relation) }
    def self.schedule_ordered; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs were completed before the given timestamp. If no timestamp is
    # provided, get all jobs that have been completed. By default, GoodJob
    # destroys jobs after they are completed and this will find no jobs.
    # However, if you have changed {GoodJob.preserve_job_records}, this may
    # find completed Jobs.
    # 
    # _@param_ `timestamp` — Get jobs that finished before this time (in epoch time).
    sig { params(timestamp: T.nilable(Float)).returns(ActiveRecord::Relation) }
    def self.finished(timestamp = nil); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs have errored that will not be retried further
    sig { returns(ActiveRecord::Relation) }
    def self.running; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs on queues that match the given queue string.
    # 
    # _@param_ `string` — A string expression describing what queues to select. See {Execution.queue_parser} or {file:README.md#optimize-queues-threads-and-processes} for more details on the format of the string. Note this only handles individual semicolon-separated segments of that string format.
    sig { params(string: String).returns(ActiveRecord::Relation) }
    def self.queue_string(string); end

    # Finds the next eligible Execution, acquire an advisory lock related to it, and
    # executes the job.
    # 
    # _@return_ — If a job was executed, returns an array with the {Execution} record, the
    # return value for the job's +#perform+ method, and the exception the job
    # raised, if any (if the job raised, then the second array entry will be
    # +nil+). If there were no jobs to execute, returns +nil+.
    sig { returns(T.nilable(ExecutionResult)) }
    def self.perform_with_advisory_lock; end

    # Fetches the scheduled execution time of the next eligible Execution(s).
    # 
    # _@param_ `after`
    # 
    # _@param_ `limit`
    # 
    # _@param_ `now_limit`
    sig { params(after: T.nilable(DateTime), limit: Integer, now_limit: T.nilable(Integer)).returns(T::Array[DateTime]) }
    def self.next_scheduled_at(after: nil, limit: 100, now_limit: nil); end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Places an ActiveJob job on a queue by creating a new {Execution} record.
    # 
    # _@param_ `active_job` — The job to enqueue.
    # 
    # _@param_ `scheduled_at` — Epoch timestamp when the job should be executed.
    # 
    # _@param_ `create_with_advisory_lock` — Whether to establish a lock on the {Execution} record after it is created.
    # 
    # _@return_ — The new {Execution} instance representing the queued ActiveJob job.
    sig { params(active_job: ActiveJob::Base, scheduled_at: T.nilable(Float), create_with_advisory_lock: T::Boolean).returns(Execution) }
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false); end

    # Execute the ActiveJob job this {Execution} represents.
    # 
    # _@return_ — An array of the return value of the job's +#perform+ method and the
    # exception raised by the job, if any. If the job completed successfully,
    # the second array entry (the exception) will be +nil+ and vice versa.
    sig { returns(ExecutionResult) }
    def perform; end

    # Tests whether this job is safe to be executed by this thread.
    sig { returns(T::Boolean) }
    def executable?; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def active_job; end

    # There are 3 buckets of non-overlapping statuses:
    #   1. The job will be executed
    #     - queued: The job will execute immediately when an execution thread becomes available.
    #     - scheduled: The job is scheduled to execute in the future.
    #     - retried: The job previously errored on execution and will be re-executed in the future.
    #   2. The job is being executed
    #     - running: the job is actively being executed by an execution thread
    #   3. The job will not execute
    #     - finished: The job executed successfully
    #     - discarded: The job previously errored on execution and will not be re-executed in the future.
    sig { returns(Symbol) }
    def status; end

    sig { returns(T::Boolean) }
    def running?; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def number; end

    # sord omit - no YARD return type given, using untyped
    # The last relevant timestamp for this execution
    sig { returns(T.untyped) }
    def last_status_at; end

    # sord omit - no YARD return type given, using untyped
    # Time between when this job was expected to run and when it started running
    sig { returns(T.untyped) }
    def queue_latency; end

    # sord omit - no YARD return type given, using untyped
    # Time between when this job started and finished
    sig { returns(T.untyped) }
    def runtime_latency; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def active_job_data; end

    sig { returns(ExecutionResult) }
    def execute; end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@param_ `key` — Key to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was acquired.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was released.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — +true+
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function); end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(Object) }
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Tests whether this record has an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_locked?(key: lockable_key); end

    # Tests whether this record does not have an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlocked?(key: lockable_key); end

    # Tests whether this record is locked by the current database session.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def owns_advisory_lock?(key: lockable_key); end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).void }
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Default Advisory Lock key
    sig { returns(String) }
    def lockable_key; end

    # sord omit - no YARD type given for "column:", using untyped
    # Default Advisory Lock key for column-based locking
    sig { params(column: T.untyped).returns(String) }
    def lockable_column_key(column: self.class._advisory_lockable_column); end
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
      sig { returns(T.nilable(T::Array[GoodJob::Scheduler])) }
      attr_reader :instances
    end

    # Creates GoodJob::Scheduler(s) and Performers from a GoodJob::Configuration instance.
    # 
    # _@param_ `configuration`
    # 
    # _@param_ `warm_cache_on_initialize`
    sig { params(configuration: GoodJob::Configuration, warm_cache_on_initialize: T::Boolean).returns(T.any(GoodJob::Scheduler, GoodJob::MultiScheduler)) }
    def self.from_configuration(configuration, warm_cache_on_initialize: false); end

    # _@param_ `performer`
    # 
    # _@param_ `max_threads` — number of seconds between polls for jobs
    # 
    # _@param_ `max_cache` — maximum number of scheduled jobs to cache in memory
    # 
    # _@param_ `warm_cache_on_initialize` — whether to warm the cache immediately, or manually by calling +warm_cache+
    # 
    # _@param_ `cleanup_interval_seconds` — number of seconds between cleaning up job records
    # 
    # _@param_ `cleanup_interval_jobs` — number of executed jobs between cleaning up job records
    sig do
      params(
        performer: GoodJob::JobPerformer,
        max_threads: T.nilable(Numeric),
        max_cache: T.nilable(Numeric),
        warm_cache_on_initialize: T::Boolean,
        cleanup_interval_seconds: T.nilable(Numeric),
        cleanup_interval_jobs: T.nilable(Numeric)
      ).void
    end
    def initialize(performer, max_threads: nil, max_cache: nil, warm_cache_on_initialize: false, cleanup_interval_seconds: nil, cleanup_interval_jobs: nil); end

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
    # _@param_ `timeout` — Seconds to wait for actively executing jobs to finish * +nil+, the scheduler will trigger a shutdown but not wait for it to complete. * +-1+, the scheduler will wait until the shutdown is complete. * +0+, the scheduler will immediately shutdown and stop any active tasks. * A positive number will wait that many seconds before stopping any remaining active tasks.
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1); end

    # Restart the Scheduler.
    # When shutdown, start; or shutdown and start.
    # 
    # _@param_ `timeout` — Seconds to wait for actively executing jobs to finish; shares same values as {#shutdown}.
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1); end

    # Wakes a thread to allow the performer to execute a task.
    # 
    # _@param_ `state` — Contextual information for the performer. See {JobPerformer#next?}.
    # 
    # _@return_ — Whether work was started.
    # 
    # * +nil+ if the scheduler is unable to take new work, for example if the thread pool is shut down or at capacity.
    # * +true+ if the performer started executing work.
    # * +false+ if the performer decides not to attempt to execute a task based on the +state+ that is passed to it.
    sig { params(state: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T.nilable(T::Boolean)) }
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

    # Preload existing runnable and future-scheduled jobs
    sig { void }
    def warm_cache; end

    # Preload existing runnable and future-scheduled jobs
    sig { void }
    def cleanup; end

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

    # Human readable name of the scheduler that includes configuration values.
    sig { returns(String) }
    attr_reader :name

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
      # Number of scheduled jobs in the queue
      sig { returns(Integer) }
      def length; end

      # Clear the queue
      sig { void }
      def reset; end
    end
  end

  # 
  # A CronEntry represents a single scheduled item's properties.
  class CronEntry
    include ActiveModel::Model

    # sord omit - no YARD type given for "configuration:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(configuration: T.untyped).returns(T.untyped) }
    def self.all(configuration: nil); end

    # sord omit - no YARD type given for "key", using untyped
    # sord omit - no YARD type given for "configuration:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(key: T.untyped, configuration: T.untyped).returns(T.untyped) }
    def self.find(key, configuration: nil); end

    # sord omit - no YARD type given for "params", using untyped
    sig { params(params: T.untyped).void }
    def initialize(params = {}); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def key; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def job_class; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def cron; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def set; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def args; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def kwargs; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def description; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def next_at; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def schedule; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def fugit; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def jobs; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def last_at; end

    # sord omit - no YARD type given for "cron_at", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(cron_at: T.untyped).returns(T.untyped) }
    def enqueue(cron_at = nil); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def last_job; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def display_properties; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def set_value; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def args_value; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def kwargs_value; end

    # sord omit - no YARD type given for "value", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(value: T.untyped).returns(T.untyped) }
    def display_property(value); end

    # sord omit - no YARD type given for :params, using untyped
    # Returns the value of attribute params.
    sig { returns(T.untyped) }
    attr_reader :params
  end

  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module Filterable
    extend ActiveSupport::Concern

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get records in display order with optional keyset pagination.
    # 
    # _@param_ `after_scheduled_at` — Display records scheduled after this time for keyset pagination
    # 
    # _@param_ `after_id` — Display records after this ID for keyset pagination
    sig { params(after_scheduled_at: T.nilable(T.any(DateTime, String)), after_id: T.nilable(T.any(Numeric, String))).returns(ActiveRecord::Relation) }
    def self.display_all(after_scheduled_at: nil, after_id: nil); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Search records by text query.
    # 
    # _@param_ `query` — Search Query
    sig { params(query: String).returns(ActiveRecord::Relation) }
    def self.search_text(query); end

    sig { returns(T::Boolean) }
    def self.database_supports_websearch_to_tsquery?; end
  end

  # Base ActiveRecord class that all GoodJob models inherit from.
  # Parent class can be configured with +GoodJob.active_record_parent_class+.
  # @!parse
  #   class BaseRecord < ActiveRecord::Base; end
  class BaseRecord < ActiveRecord::Base
    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def self.migration_pending_warning!; end
  end

  # 
  # CronManagers enqueue jobs on a repeating schedule.
  class CronManager
    class << self
      # List of all instantiated CronManagers in the current process.
      sig { returns(T.nilable(T::Array[GoodJob::CronManager])) }
      attr_reader :instances
    end

    # sord omit - no YARD return type given, using untyped
    # Task observer for cron task
    # 
    # _@param_ `time`
    # 
    # _@param_ `output`
    # 
    # _@param_ `thread_error`
    sig { params(time: Time, output: Object, thread_error: T.nilable(Exception)).returns(T.untyped) }
    def self.task_observer(time, output, thread_error); end

    # _@param_ `cron_entries`
    # 
    # _@param_ `start_on_initialize`
    sig { params(cron_entries: T::Array[CronEntry], start_on_initialize: T::Boolean).void }
    def initialize(cron_entries = [], start_on_initialize: false); end

    # sord omit - no YARD return type given, using untyped
    # Schedule tasks that will enqueue jobs based on their schedule
    sig { returns(T.untyped) }
    def start; end

    # sord omit - no YARD return type given, using untyped
    # Stop/cancel any scheduled tasks
    # 
    # _@param_ `timeout` — Unused but retained for compatibility
    sig { params(timeout: T.nilable(Numeric)).returns(T.untyped) }
    def shutdown(timeout: nil); end

    # sord omit - no YARD return type given, using untyped
    # Stop and restart
    # 
    # _@param_ `timeout` — Unused but retained for compatibility
    sig { params(timeout: T.nilable(Numeric)).returns(T.untyped) }
    def restart(timeout: nil); end

    # Tests whether the manager is running.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Tests whether the manager is shutdown.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # sord omit - no YARD return type given, using untyped
    # Enqueues a scheduled task
    # 
    # _@param_ `cron_entry` — the CronEntry object to schedule
    sig { params(cron_entry: CronEntry).returns(T.untyped) }
    def create_task(cron_entry); end

    # Execution configuration to be scheduled
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :cron_entries
  end

  # Extends GoodJob module to track Rails boot dependencies.
  module Dependencies
    extend ActiveSupport::Concern

    class << self
      # Whether Railtie.after_initialize has been called yet (default: +false+).
      # This will be set on  but before +Rails.application.initialize?+ is +true+.
      sig { returns(T::Boolean) }
      attr_accessor :_rails_after_initialize_hook_called

      # Whether ActiveJob has loaded (default: +false+).
      sig { returns(T::Boolean) }
      attr_accessor :_active_job_loaded

      # Whether ActiveRecord has loaded (default: +false+).
      sig { returns(T::Boolean) }
      attr_accessor :_active_record_loaded
    end

    # Whether GoodJob's  has been initialized as of the calling of +Railtie.after_initialize+.
    sig { returns(T::Boolean) }
    def self.async_ready?; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def self.start_async_adapters; end
  end

  class ProbeServer
    RACK_SERVER = T.let('webrick', T.untyped)

    # sord omit - no YARD type given for "time", using untyped
    # sord omit - no YARD type given for "output", using untyped
    # sord omit - no YARD type given for "thread_error", using untyped
    # sord omit - no YARD return type given, using untyped
    # rubocop:disable Lint/UnusedMethodArgument
    sig { params(time: T.untyped, output: T.untyped, thread_error: T.untyped).returns(T.untyped) }
    def self.task_observer(time, output, thread_error); end

    # sord omit - no YARD type given for "port:", using untyped
    sig { params(port: T.untyped).void }
    def initialize(port:); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def start; end

    sig { returns(T::Boolean) }
    def running?; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def stop; end

    # sord omit - no YARD type given for "env", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(env: T.untyped).returns(T.untyped) }
    def call(env); end
  end

  # 
  # +GoodJob::Configuration+ provides normalized configuration information to
  # the rest of GoodJob. It combines environment information with explicitly
  # set options to get the final values for each option.
  class Configuration
    EXECUTION_MODES = T.let([:async, :async_all, :async_server, :external, :inline].freeze, T.untyped)
    DEFAULT_MAX_THREADS = T.let(5, T.untyped)
    DEFAULT_POLL_INTERVAL = T.let(10, T.untyped)
    DEFAULT_DEVELOPMENT_ASYNC_POLL_INTERVAL = T.let(-1
# Default number of threads to use per {Scheduler}, T.untyped)
    DEFAULT_MAX_CACHE = T.let(10000, T.untyped)
    DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO = T.let(24 * 60 * 60, T.untyped)
    DEFAULT_CLEANUP_INTERVAL_JOBS = T.let(nil, T.untyped)
    DEFAULT_CLEANUP_INTERVAL_SECONDS = T.let(nil, T.untyped)
    DEFAULT_SHUTDOWN_TIMEOUT = T.let(-1
# Default to not running cron, T.untyped)
    DEFAULT_ENABLE_CRON = T.let(false, T.untyped)

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

    sig { returns(T::Boolean) }
    def inline_execution_respects_schedule?; end

    # The maximum number of future-scheduled jobs to store in memory.
    # Storing future-scheduled jobs in memory reduces execution latency
    # at the cost of increased memory usage. 10,000 stored jobs = ~20MB.
    sig { returns(Integer) }
    def max_cache; end

    # The number of seconds to wait for jobs to finish when shutting down
    # before stopping the thread. +-1+ is forever.
    sig { returns(Numeric) }
    def shutdown_timeout; end

    # Whether to run cron
    sig { returns(T::Boolean) }
    def enable_cron; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def cron; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def cron_entries; end

    # Whether to destroy discarded jobs when cleaning up preserved jobs.
    # This configuration is only used when {GoodJob.preserve_job_records} is +true+.
    sig { returns(T::Boolean) }
    def cleanup_discarded_jobs?; end

    # Number of seconds to preserve jobs when using the +good_job cleanup_preserved_jobs+ CLI command.
    # This configuration is only used when {GoodJob.preserve_job_records} is +true+.
    sig { returns(Integer) }
    def cleanup_preserved_jobs_before_seconds_ago; end

    # Number of jobs a {Scheduler} will execute before cleaning up preserved jobs.
    sig { returns(T.nilable(Integer)) }
    def cleanup_interval_jobs; end

    # Number of seconds a {Scheduler} will wait before cleaning up preserved jobs.
    sig { returns(T.nilable(Integer)) }
    def cleanup_interval_seconds; end

    # Tests whether to daemonize the process.
    sig { returns(T::Boolean) }
    def daemonize?; end

    # Path of the pidfile to create when running as a daemon.
    sig { returns(T.any(Pathname, String)) }
    def pidfile; end

    # Port of the probe server
    sig { void }
    def probe_port; end

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
    sig { returns(T.nilable(Object)) }
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
    sig { params(after: T.nilable(T.any(DateTime, Time)), limit: T.nilable(Integer), now_limit: T.nilable(Integer)).returns(T.nilable(T::Array[T.any(DateTime, Time)])) }
    def next_at(after: nil, limit: nil, now_limit: nil); end

    # Destroy expired preserved jobs
    sig { void }
    def cleanup; end

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

  # ActiveRecord model that represents an +ActiveJob+ job.
  # There is not a table in the database whose discrete rows represents "Jobs".
  # The +good_jobs+ table is a table of individual {GoodJob::Execution}s that share the same +active_job_id+.
  # A single row from the +good_jobs+ table of executions is fetched to represent an ActiveJobJob
  class ActiveJobJob < GoodJob::BaseRecord
    include GoodJob::Filterable
    include GoodJob::Lockable
    ActionForStateMismatchError = T.let(Class.new(StandardError), T.untyped)
    AdapterNotGoodJobError = T.let(Class.new(StandardError), T.untyped)
    DiscardJobError = T.let(Class.new(StandardError), T.untyped)

    # sord omit - no YARD type given for "_value", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(_value: T.untyped).returns(T.untyped) }
    def self.table_name=(_value); end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs with given class name
    # 
    # _@param_ `string` — Execution class name
    sig { returns(ActiveRecord::Relation) }
    def self.job_class; end

    # sord warn - ActiveRecord::Relation wasn't able to be resolved to a constant in this project
    # Get Jobs finished before the given timestamp.
    # 
    # _@param_ `timestamp`
    sig { params(timestamp: T.any(DateTime, Time)).returns(ActiveRecord::Relation) }
    def self.finished_before(timestamp); end

    # The job's ActiveJob UUID
    sig { returns(String) }
    def id; end

    # The ActiveJob job class, as a string
    sig { returns(String) }
    def job_class; end

    # The status of the Job, based on the state of its most recent execution.
    sig { returns(Symbol) }
    def status; end

    # This job's most recent {Execution}
    # 
    # _@param_ `reload` — whether to reload executions
    sig { params(reload: T::Boolean).returns(Execution) }
    def head_execution(reload: false); end

    # This job's initial/oldest {Execution}
    sig { returns(Execution) }
    def tail_execution; end

    # The number of times this job has been executed, according to ActiveJob's serialized state.
    sig { returns(Numeric) }
    def executions_count; end

    # The number of times this job has been executed, according to the number of GoodJob {Execution} records.
    sig { returns(Numeric) }
    def preserved_executions_count; end

    # The most recent error message.
    # If the job has been retried, the error will be fetched from the previous {Execution} record.
    sig { returns(String) }
    def recent_error; end

    # Tests whether the job is being executed right now.
    sig { returns(T::Boolean) }
    def running?; end

    # sord warn - ActiveJob::Base wasn't able to be resolved to a constant in this project
    # Retry a job that has errored and been discarded.
    # This action will create a new {Execution} record for the job.
    sig { returns(ActiveJob::Base) }
    def retry_job; end

    # sord omit - no YARD type given for "message", using untyped
    # Discard a job so that it will not be executed further.
    # This action will add a {DiscardJobError} to the job's {Execution} and mark it as finished.
    sig { params(message: T.untyped).void }
    def discard_job(message); end

    # Reschedule a scheduled job so that it executes immediately (or later) by the next available execution thread.
    # 
    # _@param_ `scheduled_at` — When to reschedule the job
    sig { params(scheduled_at: T.any(DateTime, Time)).void }
    def reschedule_job(scheduled_at = Time.current); end

    # Destroy all of a discarded or finished job's executions from the database so that it will no longer appear on the dashboard.
    sig { void }
    def destroy_job; end

    # Utility method to determine which execution record is used to represent this job
    sig { returns(String) }
    def _execution_id; end

    # Utility method to test whether this job's underlying attributes represents its most recent execution.
    sig { returns(T::Boolean) }
    def _head?; end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # 
    # _@param_ `key` — Key to Advisory Lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was acquired.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — whether the lock was released.
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — +true+
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function); end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    # 
    # _@return_ — The result of the block.
    # 
    # ```ruby
    # record = MyLockableRecord.first
    # record.with_advisory_lock do
    #   do_something_with record
    # end
    # ```
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).returns(Object) }
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function); end

    # Tests whether this record has an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_locked?(key: lockable_key); end

    # Tests whether this record does not have an advisory lock on it.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def advisory_unlocked?(key: lockable_key); end

    # Tests whether this record is locked by the current database session.
    # 
    # _@param_ `key` — Key to test lock against
    sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
    def owns_advisory_lock?(key: lockable_key); end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # 
    # _@param_ `key` — Key to lock against
    # 
    # _@param_ `function` — Postgres Advisory Lock function name to use
    sig { params(key: T.any(String, Symbol), function: T.any(String, Symbol)).void }
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function)); end

    # Default Advisory Lock key
    sig { returns(String) }
    def lockable_key; end

    # sord omit - no YARD type given for "column:", using untyped
    # Default Advisory Lock key for column-based locking
    sig { params(column: T.untyped).returns(String) }
    def lockable_column_key(column: self.class._advisory_lockable_column); end
  end

  # Thread-local attributes for passing values from Instrumentation.
  # (Cannot use ActiveSupport::CurrentAttributes because ActiveJob resets it)
  module CurrentThread
    ACCESSORS = T.let(%i[
  cron_at
  cron_key
  error_on_discard
  error_on_retry
  execution
].freeze, T.untyped)

    class << self
      # Cron At
      sig { returns(T.nilable(DateTime)) }
      attr_accessor :cron_at

      # Cron Key
      sig { returns(T.nilable(String)) }
      attr_accessor :cron_key

      # Error captured by discard_on
      sig { returns(T.nilable(Exception)) }
      attr_accessor :error_on_discard

      # Error captured by retry_on
      sig { returns(T.nilable(Exception)) }
      attr_accessor :error_on_retry

      # Execution
      sig { returns(T.nilable(GoodJob::Execution)) }
      attr_accessor :executions
    end

    # Resets attributes
    # 
    # _@param_ `values` — to assign
    sig { params(values: T::Hash[T.untyped, T.untyped]).void }
    def self.reset(values = {}); end

    # Exports values to hash
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def self.to_h; end

    # _@return_ — UUID of the currently executing GoodJob::Execution
    sig { returns(String) }
    def self.active_job_id; end

    # _@return_ — Current process ID
    sig { returns(Integer) }
    def self.process_id; end

    # _@return_ — Current thread name
    sig { returns(String) }
    def self.thread_name; end

    # Wrap the yielded block with CurrentThread values and reset after the block
    sig { void }
    def self.within; end
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
    def cron_manager_start(event); end

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

  # Tracks thresholds for cleaning up old jobs.
  class CleanupTracker
    # sord omit - no YARD type given for "cleanup_interval_seconds:", using untyped
    # sord omit - no YARD type given for "cleanup_interval_jobs:", using untyped
    sig { params(cleanup_interval_seconds: T.untyped, cleanup_interval_jobs: T.untyped).void }
    def initialize(cleanup_interval_seconds: nil, cleanup_interval_jobs: nil); end

    # Increments job count.
    sig { void }
    def increment; end

    # Whether a cleanup should be run.
    sig { returns(T::Boolean) }
    def cleanup?; end

    # Resets the counters.
    sig { void }
    def reset; end

    # Returns the value of attribute cleanup_interval_seconds.
    sig { returns(T.untyped) }
    attr_accessor :cleanup_interval_seconds

    # Returns the value of attribute cleanup_interval_jobs.
    sig { returns(T.untyped) }
    attr_accessor :cleanup_interval_jobs

    # Returns the value of attribute job_count.
    sig { returns(T.untyped) }
    attr_accessor :job_count

    # Returns the value of attribute last_at.
    sig { returns(T.untyped) }
    attr_accessor :last_at
  end

  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # _@param_ `schedulers`
    sig { params(schedulers: T::Array[Scheduler]).void }
    def initialize(schedulers); end

    # Delegates to {Scheduler#running?}.
    sig { returns(T.nilable(T::Boolean)) }
    def running?; end

    # Delegates to {Scheduler#shutdown?}.
    sig { returns(T.nilable(T::Boolean)) }
    def shutdown?; end

    # Delegates to {Scheduler#shutdown}.
    # 
    # _@param_ `timeout`
    sig { params(timeout: T.nilable(Numeric)).void }
    def shutdown(timeout: -1); end

    # Delegates to {Scheduler#restart}.
    # 
    # _@param_ `timeout`
    sig { params(timeout: T.nilable(Numeric)).void }
    def restart(timeout: -1); end

    # Delegates to {Scheduler#create_thread}.
    # 
    # _@param_ `state`
    sig { params(state: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T.nilable(T::Boolean)) }
    def create_thread(state = nil); end

    # _@return_ — List of the scheduler delegates
    sig { returns(T::Array[Scheduler]) }
    attr_reader :schedulers
  end

  # Stores the results of job execution
  class ExecutionResult
    # _@param_ `value`
    # 
    # _@param_ `handled_error`
    # 
    # _@param_ `unhandled_error`
    sig { params(value: T.nilable(Object), handled_error: T.nilable(Exception), unhandled_error: T.nilable(Exception)).void }
    def initialize(value:, handled_error: nil, unhandled_error: nil); end

    sig { returns(T.nilable(Object)) }
    attr_reader :value

    sig { returns(T.nilable(Exception)) }
    attr_reader :handled_error

    sig { returns(T.nilable(Exception)) }
    attr_reader :unhandled_error
  end

  module ActiveJobExtensions
    module Concurrency
      extend ActiveSupport::Concern

      # sord omit - no YARD type given for "config", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(config: T.untyped).returns(T.untyped) }
      def self.good_job_control_concurrency_with(config); end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def good_job_concurrency_key; end

      class ConcurrencyExceededError < StandardError
        # sord omit - no YARD return type given, using untyped
        sig { returns(T.untyped) }
        def backtrace; end
      end
    end
  end

  # Extends an ActiveRecord odel to override the connection and use
  # an explicit connection that has been removed from the pool.
  module AssignableConnection
    extend ActiveSupport::Concern

    # sord warn - ActiveRecord::ConnectionAdapters::AbstractAdapter wasn't able to be resolved to a constant in this project
    # Assigns a connection to the model.
    # 
    # _@param_ `conn`
    sig { params(conn: ActiveRecord::ConnectionAdapters::AbstractAdapter).void }
    def self.connection=(conn); end

    # sord warn - ActiveRecord::ConnectionAdapters::AbstractAdapter wasn't able to be resolved to a constant in this project
    # Overrides the existing connection method to use the assigned connection
    sig { returns(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
    def self.connection; end

    # sord warn - ActiveRecord::ConnectionAdapters::AbstractAdapter wasn't able to be resolved to a constant in this project
    # Block interface to assign the connection, yield, then unassign the connection.
    # 
    # _@param_ `conn`
    sig { params(conn: ActiveRecord::ConnectionAdapters::AbstractAdapter).void }
    def self.with_connection(conn); end
  end

  # 
  # Rails generator used for updating GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:update+ in your console.
  class UpdateGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration
    TEMPLATES = T.let(File.join(File.dirname(__FILE__), "templates/update"), T.untyped)

    # sord omit - no YARD return type given, using untyped
    # Generates incremental migration files unless they already exist.
    # All migrations should be idempotent e.g. +add_index+ is guarded with +if_index_exists?+
    sig { returns(T.untyped) }
    def update_migration_files; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def migration_version; end
  end

  # 
  # Rails generator used for setting up GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:install+ in your console.
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration
    TEMPLATES = T.let(File.join(File.dirname(__FILE__), "templates/install"), T.untyped)

    # sord omit - no YARD return type given, using untyped
    # Generates monolithic migration file that contains all database changes.
    sig { returns(T.untyped) }
    def create_migration_file; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def migration_version; end
  end
end

# typed: strict
# frozen_string_literal: true
module ActiveJob
  # :nodoc:
  module QueueAdapters
    # See {GoodJob::Adapter} for details.
    class GoodJobAdapter < GoodJob::Adapter
    end
  end
end
