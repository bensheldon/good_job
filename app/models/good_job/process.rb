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
    PROCESS_MEMORY = case RUBY_PLATFORM
                     when /linux/
                       lambda do |pid|
                         File.readlines("/proc/#{pid}/smaps_rollup").each do |line|
                           next unless line.start_with?('Pss:')

                           break line.split[1].to_i
                         end
                       rescue Errno::ENOENT
                         File.readlines("/proc/#{pid}/status").each do |line|
                           next unless line.start_with?('VmRSS:')

                           break line.split[1].to_i
                         end
                       end
                     when /darwin|bsd/
                       lambda do |pid|
                         `ps -o pid,rss -p #{pid.to_i}`.lines.last.split.last.to_i
                       end
                     else
                       ->(_pid) { 0 }
                     end

    self.table_name = 'good_job_processes'
    self.implicit_order_column = 'created_at'

    lock_type_enum = {
      advisory: 0,
    }
    if Gem::Version.new(Rails.version) >= Gem::Version.new('7.1.0.a')
      enum :lock_type, lock_type_enum, validate: { allow_nil: true }, scopes: false
    else
      enum lock_type: lock_type_enum, _scopes: false
    end

    has_many :locked_jobs, class_name: "GoodJob::Job", foreign_key: :locked_by_id, inverse_of: :locked_by_process, dependent: nil
    after_destroy { locked_jobs.update_all(locked_by_id: nil) } # rubocop:disable Rails/SkipsModelValidations

    # Processes that are active and locked.
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :active, (lambda do
      query = joins_advisory_locks
      query.where(lock_type: :advisory).advisory_locked
        .or(query.where(lock_type: nil).where(arel_table[:updated_at].gt(EXPIRED_INTERVAL.ago)))
    end)

    # Processes that are inactive and unlocked (e.g. SIGKILLed)
    # @!method active
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :inactive, (lambda do
      query = joins_advisory_locks
      query.where(lock_type: :advisory).advisory_unlocked
        .or(query.where(lock_type: nil).where(arel_table[:updated_at].lt(EXPIRED_INTERVAL.ago)))
    end)

    # Deletes all inactive process records.
    def self.cleanup
      inactive.find_each do |process|
        GoodJob::Job.where(locked_by_id: process.id).update_all(locked_by_id: nil, locked_at: nil) # rubocop:disable Rails/SkipsModelValidations
        process.delete
      end
    end

    # @return [Integer]
    def self.memory_usage(pid)
      PROCESS_MEMORY.call(pid)
    rescue StandardError
      0
    end

    def self.find_or_create_record(id:, with_advisory_lock: false)
      attributes = {
        id: id,
        state: process_state,
      }
      if with_advisory_lock
        attributes[:create_with_advisory_lock] = true
        attributes[:lock_type] = :advisory
      end
      create!(attributes)
    rescue ActiveRecord::RecordNotUnique
      find_by(id: id).tap do |existing_record|
        next unless existing_record

        if with_advisory_lock
          existing_record.advisory_lock!
          existing_record.update(lock_type: :advisory, state: process_state, updated_at: Time.current)
        else
          existing_record.update(lock_type: nil, state: process_state, updated_at: Time.current)
        end
      end
    end

    def self.process_state
      {
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        memory: memory_usage(::Process.pid),
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
      reload # verify the record still exists in the database
      self.state = self.class.process_state
      update(state: state, updated_at: Time.current)
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
  end
end

ActiveSupport.run_load_hooks(:good_job_process, GoodJob::Process)
