module GoodJob
  #
  # Represents a request to perform an +ActiveJob+ job.
  #
  class Job < ActiveRecord::Base
    include Lockable

    # Raised if something attempts to execute a previously completed Job again.
    PreviouslyPerformedError = Class.new(StandardError)

    # ActiveJob jobs without a +queue_name+ attribute are placed on this queue.
    DEFAULT_QUEUE_NAME = 'default'.freeze
    # ActiveJob jobs without a +priority+ attribute are given this priority.
    DEFAULT_PRIORITY = 0

    self.table_name = 'good_jobs'.freeze

    # Parse a string representing a group of queues into a more readable data
    # structure.
    # @return [Hash]
    #   How to match a given queue. It can have the following keys and values:
    #   - +{ all: true }+ indicates that all queues match.
    #   - +{ exclude: Array<String> }+ indicates the listed queue names should
    #     not match.
    #   - +{ include: Array<String> }+ indicates the listed queue names should
    #     match.
    # @example
    #   GoodJob::Job.queue_parser('-queue1,queue2')
    #   => { exclude: [ 'queue1', 'queue2' ] }
    def self.queue_parser(string)
      string = string.presence || '*'

      if string.first == '-'
        exclude_queues = true
        string = string[1..-1]
      end

      queues = string.split(',').map(&:strip)

      if queues.include?('*')
        { all: true }
      elsif exclude_queues
        { exclude: queues }
      else
        { include: queues }
      end
    end

    # Get Jobs that have not yet been completed.
    # @!method unfinished
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :unfinished, (lambda do
      if column_names.include?('finished_at')
        where(finished_at: nil)
      else
        ActiveSupport::Deprecation.warn('GoodJob expects a good_jobs.finished_at column to exist. Please see the GoodJob README.md for migration instructions.')
        nil
      end
    end)

    # Get Jobs that are not scheduled for a later time than now (i.e. jobs that
    # are not scheduled or scheduled for earlier than the current time).
    # @!method only_scheduled
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(Time.current)).or(where(scheduled_at: nil)) }

    # Order jobs by priority (highest priority first).
    # @!method priority_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :priority_ordered, -> { order('priority DESC NULLS LAST') }

    # Get Jobs were completed before the given timestamp. If no timestamp is
    # provided, get all jobs that have been completed. By default, GoodJob
    # deletes jobs after they are completed and this will find no jobs.
    # However, if you have changed {GoodJob.preserve_job_records}, this may
    # find completed Jobs.
    # @!method finished(timestamp = nil)
    # @!scope class
    # @param timestamp (Float)
    #   Get jobs that finished before this time (in epoch time).
    # @return [ActiveRecord::Relation]
    scope :finished, ->(timestamp = nil) { timestamp ? where(arel_table['finished_at'].lteq(timestamp)) : where.not(finished_at: nil) }

    # Get Jobs on queues that match the given queue string.
    # @!method queue_string(string)
    # @!scope class
    # @param string [String]
    #   A string expression describing what queues to select. See
    #   {Job.queue_parser} or
    #   {file:README.md#optimize-queues-threads-and-processes} for more details
    #   on the format of the string. Note this only handles individual
    #   semicolon-separated segments of that string format.
    # @return [ActiveRecord::Relation]
    scope :queue_string, (lambda do |string|
      parsed = queue_parser(string)

      if parsed[:all]
        all
      elsif parsed[:exclude]
        where.not(queue_name: parsed[:exclude]).or where(queue_name: nil)
      elsif parsed[:include]
        where(queue_name: parsed[:include])
      end
    end)

    # Get Jobs in display order with optional keyset pagination.
    # @!method display_all(after_scheduled_at: nil, after_id: nil)
    # @!scope class
    # @param after_scheduled_at [DateTime, String, nil]
    #   Display records scheduled after this time for keyset pagination
    # @param after_id [Numeric, String, nil]
    #   Display records after this ID for keyset pagination
    # @return [ActiveRecord::Relation]
    scope :display_all, (lambda do |after_scheduled_at: nil, after_id: nil|
      query = order(Arel.sql('COALESCE(scheduled_at, created_at) DESC, id DESC'))
      if after_scheduled_at.present? && after_id.present?
        query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at), id) < (:after_scheduled_at, :after_id)'), after_scheduled_at: after_scheduled_at, after_id: after_id)
      elsif after_scheduled_at.present?
        query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at)) < (:after_scheduled_at)'), after_scheduled_at: after_scheduled_at)
      end
      query
    end)

    # Finds the next eligible Job, acquire an advisory lock related to it, and
    # executes the job.
    # @return [Array<(GoodJob::Job, Object, Exception)>, nil]
    #   If a job was executed, returns an array with the {Job} record, the
    #   return value for the job's +#perform+ method, and the exception the job
    #   raised, if any (if the job raised, then the second array entry will be
    #   +nil+). If there were no jobs to execute, returns +nil+.
    def self.perform_with_advisory_lock
      good_job = nil
      result = nil
      error = nil

      unfinished.priority_ordered.only_scheduled.limit(1).with_advisory_lock do |good_jobs|
        good_job = good_jobs.first
        # TODO: Determine why some records are fetched without an advisory lock at all
        break unless good_job&.owns_advisory_lock?

        result, error = good_job.perform
      end

      [good_job, result, error] if good_job
    end

    # Places an ActiveJob job on a queue by creating a new {Job} record.
    # @param active_job [ActiveJob::Base]
    #   The job to enqueue.
    # @param scheduled_at [Float]
    #   Epoch timestamp when the job should be executed.
    # @param create_with_advisory_lock [Boolean]
    #   Whether to establish a lock on the {Job} record after it is created.
    # @return [Job]
    #   The new {Job} instance representing the queued ActiveJob job.
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      good_job = nil
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        good_job = GoodJob::Job.new(
          queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
          priority: active_job.priority || DEFAULT_PRIORITY,
          serialized_params: active_job.serialize,
          scheduled_at: scheduled_at,
          create_with_advisory_lock: create_with_advisory_lock
        )

        instrument_payload[:good_job] = good_job

        good_job.save!
        active_job.provider_job_id = good_job.id
      end

      good_job
    end

    # Execute the ActiveJob job this {Job} represents.
    # @return [Array<(Object, Exception)>]
    #   An array of the return value of the job's +#perform+ method and the
    #   exception raised by the job, if any. If the job completed successfully,
    #   the second array entry (the exception) will be +nil+ and vice versa.
    def perform
      raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

      GoodJob::CurrentExecution.reset

      self.performed_at = Time.current
      save! if GoodJob.preserve_job_records

      result, unhandled_error = execute

      result_error = nil
      if result.is_a?(Exception)
        result_error = result
        result = nil
      end

      job_error = unhandled_error ||
                  result_error ||
                  GoodJob::CurrentExecution.error_on_retry ||
                  GoodJob::CurrentExecution.error_on_discard

      self.error = "#{job_error.class}: #{job_error.message}" if job_error

      if unhandled_error && GoodJob.reperform_jobs_on_standard_error
        save!
      elsif GoodJob.preserve_job_records == true || (unhandled_error && GoodJob.preserve_job_records == :on_unhandled_error)
        self.finished_at = Time.current
        save!
      else
        destroy!
      end

      [result, job_error]
    end

    private

    def execute
      params = serialized_params.merge(
        "provider_job_id" => id
      )

      ActiveSupport::Notifications.instrument("perform_job.good_job", { good_job: self, process_id: GoodJob::CurrentExecution.process_id, thread_name: GoodJob::CurrentExecution.thread_name }) do
        [ActiveJob::Base.execute(params), nil]
      end
    rescue StandardError => e
      [nil, e]
    end
  end
end
