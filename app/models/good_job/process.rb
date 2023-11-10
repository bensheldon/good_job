# frozen_string_literal: true

require 'socket'

module GoodJob # :nodoc:
  # ActiveRecord model that represents an GoodJob process (either async or CLI).
  class Process < BaseRecord
    include AdvisoryLockable
    include AssignableConnection

    # Interval until the process record being updated
    STALE_INTERVAL = 30.seconds
    # Interval until the process record is treated as expired
    EXPIRED_INTERVAL = 5.minutes

    self.table_name = 'good_job_processes'

    cattr_reader :mutex, default: Mutex.new
    cattr_accessor :_current_id, default: nil
    cattr_accessor :_pid, default: nil

    # Processes that are active and locked.
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :active, -> { advisory_locked }

    # Processes that are inactive and unlocked (e.g. SIGKILLed)
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :inactive, -> { advisory_unlocked }

    # UUID that is unique to the current process and changes when forked.
    # @return [String]
    def self.current_id
      mutex.synchronize { ns_current_id }
    end

    def self.ns_current_id
      if _current_id.nil? || _pid != ::Process.pid
        self._current_id = SecureRandom.uuid
        self._pid = ::Process.pid
      end
      _current_id
    end

    # Hash representing metadata about the current process.
    # @return [Hash]
    def self.current_state
      mutex.synchronize { ns_current_state }
    end

    def self.ns_current_state
      total_succeeded_executions_count = GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats.fetch(:succeeded_executions_count, 0) }
      total_errored_executions_count = GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats.fetch(:errored_executions_count, 0) }
      total_empty_executions_count = GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats.fetch(:empty_executions_count, 0) }

      {
        id: ns_current_id,
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        proctitle: $PROGRAM_NAME,
        preserve_job_records: GoodJob.preserve_job_records,
        retry_on_unhandled_error: GoodJob.retry_on_unhandled_error,
        schedulers: GoodJob::Scheduler.instances.map(&:stats),
        cron_enabled: GoodJob.configuration.enable_cron?,
        total_succeeded_executions_count: total_succeeded_executions_count,
        total_errored_executions_count: total_errored_executions_count,
        total_executions_count: total_succeeded_executions_count + total_errored_executions_count,
        total_empty_executions_count: total_empty_executions_count,
        database_connection_pool: {
          size: connection_pool.size,
          active: connection_pool.connections.count(&:in_use?),
        },
      }
    end

    # Deletes all inactive process records.
    def self.cleanup
      inactive.delete_all
    end

    # Registers the current process in the database
    # @return [GoodJob::Process]
    def self.register
      mutex.synchronize do
        process_state = ns_current_state
        create(id: process_state[:id], state: process_state, create_with_advisory_lock: true)
      rescue ActiveRecord::RecordNotUnique
        find(ns_current_state[:id])
      end
    end

    def refresh
      mutex.synchronize do
        reload
        update(state: self.class.ns_current_state, updated_at: Time.current)
      rescue ActiveRecord::RecordNotFound
        false
      end
    end

    # Unregisters the instance.
    def deregister
      return unless owns_advisory_lock?

      mutex.synchronize do
        destroy!
        advisory_unlock
      end
    end

    def state
      super || {}
    end

    def basename
      File.basename(state.fetch("proctitle", ""))
    end

    def schedulers
      state.fetch("schedulers", [])
    end

    def refresh_if_stale(cleanup: false)
      return unless stale?

      result = refresh
      self.class.cleanup if cleanup
      result
    end

    def stale?
      updated_at < STALE_INTERVAL.ago
    end

    def expired?
      updated_at < EXPIRED_INTERVAL.ago
    end
  end
end
