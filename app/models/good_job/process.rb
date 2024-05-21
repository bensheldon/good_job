# frozen_string_literal: true

require 'socket'

module GoodJob # :nodoc:
  # Active Record model that represents a GoodJob capsule/process (either async or CLI).
  class Process < BaseRecord
    include AdvisoryLockable
    include OverridableConnection

    # Interval until the process record being updated
    STALE_INTERVAL = 30.seconds
    # Interval until the process record is treated as expired
    EXPIRED_INTERVAL = 5.minutes

    self.table_name = 'good_job_processes'
    self.implicit_order_column = 'created_at'
    LOCK_TYPES = [
      LOCK_TYPE_ADVISORY = 'advisory',
    ].freeze

    LOCK_TYPE_ENUMS = {
      LOCK_TYPE_ADVISORY => 1,
    }.freeze

    self.table_name = 'good_job_processes'

    has_many :locked_jobs, class_name: "GoodJob::Job", foreign_key: :locked_by_id, inverse_of: :locked_by_process, dependent: nil
    after_destroy { locked_jobs.update_all(locked_by_id: nil) if GoodJob::Job.columns_hash.key?("locked_by_id") } # rubocop:disable Rails/SkipsModelValidations

    # Processes that are active and locked.
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :active, (lambda do
      if lock_type_migrated?
        query = joins_advisory_locks
        query.where(lock_type: LOCK_TYPE_ENUMS[LOCK_TYPE_ADVISORY]).advisory_locked
          .or(query.where(lock_type: nil).where(arel_table[:updated_at].gt(EXPIRED_INTERVAL.ago)))
      else
        advisory_locked
      end
    end)

    # Processes that are inactive and unlocked (e.g. SIGKILLed)
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :inactive, (lambda do
      if lock_type_migrated?
        query = joins_advisory_locks
        query.where(lock_type: LOCK_TYPE_ENUMS[LOCK_TYPE_ADVISORY]).advisory_unlocked
          .or(query.where(lock_type: nil).where(arel_table[:updated_at].lt(EXPIRED_INTERVAL.ago)))
      else
        advisory_unlocked
      end
    end)

    # Deletes all inactive process records.
    def self.cleanup
      inactive.find_each do |process|
        GoodJob::Job.where(locked_by_id: process.id).update_all(locked_by_id: nil, locked_at: nil) if GoodJob::Job.columns_hash.key?("locked_by_id") # rubocop:disable Rails/SkipsModelValidations
        process.delete
      end
    end

    # @return [Boolean]
    def self.lock_type_migrated?
      columns_hash["lock_type"].present?
    end

    def self.create_record(id:, with_advisory_lock: false)
      attributes = {
        id: id,
        state: process_state,
      }
      if with_advisory_lock
        attributes[:create_with_advisory_lock] = true
        attributes[:lock_type] = LOCK_TYPE_ADVISORY if lock_type_migrated?
      end
      create!(attributes)
    end

    def self.process_state
      {
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        proctitle: $PROGRAM_NAME,
        preserve_job_records: GoodJob.preserve_job_records,
        retry_on_unhandled_error: GoodJob.retry_on_unhandled_error,
        schedulers: GoodJob::Scheduler.instances.map(&:stats),
        cron_enabled: GoodJob.configuration.enable_cron?,
        total_succeeded_executions_count: GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats.fetch(:succeeded_executions_count) },
        total_errored_executions_count: GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats.fetch(:errored_executions_count) },
        database_connection_pool: {
          size: connection_pool.size,
          active: connection_pool.connections.count(&:in_use?),
        },
      }
    end

    def refresh
      self.state = self.class.process_state
      reload.update(state: state, updated_at: Time.current)
    rescue ActiveRecord::RecordNotFound
      @new_record = true
      self.created_at = self.updated_at = nil
      state_will_change!
      save
    end

    def refresh_if_stale(cleanup: false)
      return unless stale?

      result = refresh
      self.class.cleanup if cleanup
      result
    end

    def state
      super || {}
    end

    def stale?
      updated_at < STALE_INTERVAL.ago
    end

    def expired?
      updated_at < EXPIRED_INTERVAL.ago
    end

    def basename
      File.basename(state.fetch("proctitle", ""))
    end

    def schedulers
      state.fetch("schedulers", [])
    end

    def lock_type
      return unless self.class.columns_hash['lock_type']

      enum = super
      LOCK_TYPE_ENUMS.key(enum) if enum
    end

    def lock_type=(value)
      return unless self.class.columns_hash['lock_type']

      enum = LOCK_TYPE_ENUMS[value]
      raise(ArgumentError, "Invalid error_event: #{value}") if value && !enum

      super(enum)
    end
  end
end
