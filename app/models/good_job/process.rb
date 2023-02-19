# frozen_string_literal: true
require 'socket'

module GoodJob # :nodoc:
  # ActiveRecord model that represents an GoodJob process (either async or CLI).
  class Process < BaseRecord
    include AssignableConnection
    include Lockable

    HEARTBEAT_INTERVAL = ProcessManager::HEARTBEAT_INTERVAL
    EXPIRED_INTERVAL = ProcessManager::EXPIRED_INTERVAL

    self.table_name = 'good_job_processes'

    # Processes that are active and locked.
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :active, -> { advisory_locked.or(where('updated_at > ?', EXPIRED_INTERVAL.ago)) }

    # Processes that are inactive and unlocked (e.g. SIGKILLed)
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :inactive, -> { advisory_unlocked }

    # Processes that require a heartbeat
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :stale, -> { where('updated_at < ?', HEARTBEAT_INTERVAL.ago) }

    # Processes that have failed their heartbeat
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :expired, -> { where('updated_at < ?', EXPIRED_INTERVAL.ago) }

    def self.current_id
      ProcessManager.current_process_id
    end

    # Hash representing metadata about the current process.
    # @return [Hash]
    def self.current_state
      {
        id: current_id,
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        proctitle: $PROGRAM_NAME,
        preserve_job_records: GoodJob.preserve_job_records,
        retry_on_unhandled_error: GoodJob.retry_on_unhandled_error,
        schedulers: GoodJob::Scheduler.instances.map(&:name),
        cron_enabled: GoodJob.configuration.enable_cron?,
      }
    end

    # Deletes all inactive process records.
    def self.cleanup
      inactive.expired.delete_all
    end

    # Registers or updates the current process in the database
    # @return [GoodJob::Process]
    def self.register
      find_or_initialize_by(id: current_id).tap do |process|
        process.update!(updated_at: Time.current, state: current_state)
      end
    end

    def self.unregister
      where(id: current_id).delete_all
    end

    def stale?
      updated_at < HEARTBEAT_INTERVAL.ago
    end

    def expired?
      updated_at < EXPIRED_INTERVAL.ago
    end

    def basename
      File.basename(state["proctitle"])
    end
  end
end
