# frozen_string_literal: true
require 'socket'

module GoodJob # :nodoc:
  # ActiveRecord model that represents an GoodJob process (either async or CLI).
  class Process < BaseRecord
    include AssignableConnection
    include Lockable

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
      mutex.synchronize do
        if _current_id.nil? || _pid != ::Process.pid
          self._current_id = SecureRandom.uuid
          self._pid = ::Process.pid
        end
        _current_id
      end
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
      }
    end

    # Deletes all inactive process records.
    def self.cleanup
      inactive.delete_all
    end

    # Registers the current process in the database
    # @return [GoodJob::Process]
    def self.register
      create(id: current_id, state: current_state, create_with_advisory_lock: true)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Unregisters the instance.
    def deregister
      return unless owns_advisory_lock?

      destroy!
      advisory_unlock
    end
  end
end
