# frozen_string_literal: true

require 'concurrent/delay'

module ActiveRecord
  module Type
    class UUID < ActiveModel::Type::String # :nodoc:
      def type
        :uuid
      end
    end
  end
end

module GoodJob
  #
  # JobPerformer queries the database for jobs and performs them on behalf of a
  # {Scheduler}. It mainly functions as glue between a {Scheduler} and the jobs
  # it should be executing.
  #
  # The JobPerformer must be safe to execute across multiple threads.
  #
  class JobRowLockPerformer
    cattr_accessor :performing_active_job_ids, default: Concurrent::Set.new

    # @param queue_string [String] Queues to execute jobs from
    def initialize(queue_string, capsule: GoodJob.capsule)
      @queue_string = queue_string
      @capsule = capsule
    end

    # A meaningful name to identify the performer in logs and for debugging.
    # @return [String] The queues from which Jobs are worked
    def name
      @queue_string
    end

    # Perform the next eligible job
    # @return [Object, nil] Returns job result or +nil+ if no job was found
    def next
      result = nil
      active_job_id = nil

      @capsule.tracker.register do
        id_for_lock = @capsule.tracker.id_for_lock
        return unless id_for_lock

        relation = GoodJob::Job
        relation = relation.select(:id).unfinished.where(locked_by_id: nil)
        relation = relation.where(GoodJob::Job.arel_table['scheduled_at'].lteq(Arel.sql("__SCHEDULED_AT__"))).limit(1)
        relation = relation.queue_ordered(parsed_queues[:include]) if parsed_queues && parsed_queues[:ordered_queues] && parsed_queues[:include]
        relation = relation.priority_ordered.creation_ordered
        relation = relation.limit(1)
        relation = relation.lock('FOR UPDATE SKIP LOCKED')

        begin
          binds = [
            ActiveRecord::Relation::QueryAttribute.new('locked_by_id', id_for_lock, ActiveRecord::Type::UUID.new),
            ActiveRecord::Relation::QueryAttribute.new('locked_at', Time.current, ActiveRecord::Type::DateTime.new),
            ActiveRecord::Relation::QueryAttribute.new('scheduled_at', Time.current, ActiveRecord::Type::DateTime.new),

          ]

          jobs = GoodJob::Job.find_by_sql(GoodJob::Job.pg_or_jdbc_query(<<~SQL.squish), binds)
            UPDATE good_jobs
            SET locked_by_id = $1, locked_at = $2
            WHERE id = (#{relation.to_sql.sub('__SCHEDULED_AT__', '$3')})
            RETURNING *
          SQL

          job = jobs.first
          return unless job

          active_job_id = job.id
          performing_active_job_ids << active_job_id
          yield(job) if block_given?
          result = job.perform(id_for_lock: id_for_lock)
          job.run_callbacks(:perform_unlocked)
        ensure
          performing_active_job_ids.delete(active_job_id)
        end
      end

      result
    end

    # Tests whether this performer should be used in GoodJob's current state.
    #
    # For example, state will be a LISTEN/NOTIFY message that is passed down
    # from the Notifier to the Scheduler. The Scheduler is able to ask
    # its performer "does this message relate to you?", and if not, ignore it
    # to minimize thread wake-ups, database queries, and thundering herds.
    #
    # @return [Boolean] whether the performer's {#next} method should be
    #   called in the current state.
    def next?(state = {})
      return true unless state[:queue_name]

      if parsed_queues[:exclude]
        parsed_queues[:exclude].exclude?(state[:queue_name])
      elsif parsed_queues[:include]
        parsed_queues[:include].include?(state[:queue_name])
      else
        true
      end
    end

    # The Returns timestamps of when next tasks may be available.
    # @param after [DateTime, Time, nil] future jobs scheduled after this time
    # @param limit [Integer] number of future timestamps to return
    # @param now_limit [Integer] number of past timestamps to return
    # @return [Array<DateTime, Time>, nil]
    def next_at(after: nil, limit: nil, now_limit: nil)
      job_query.next_scheduled_at(after: after, limit: limit, now_limit: now_limit)
    end

    # Destroy expired preserved jobs
    # @return [void]
    def cleanup
      GoodJob.cleanup_preserved_jobs
    end

    private

    attr_reader :queue_string

    def job_query
      @_job_query ||= GoodJob::Job.queue_string(queue_string)
    end

    def parsed_queues
      @_parsed_queues ||= GoodJob::Job.queue_parser(queue_string)
    end
  end
end
