# frozen_string_literal: true
require 'concurrent/delay'

module GoodJob
  #
  # JobPerformer queries the database for jobs and performs them on behalf of a
  # {Scheduler}. It mainly functions as glue between a {Scheduler} and the jobs
  # it should be executing.
  #
  # The JobPerformer must be safe to execute across multiple threads.
  #
  class JobPerformer
    # @param queue_string [String] Queues to execute jobs from
    def initialize(queue_string)
      @queue_string = queue_string
    end

    # A meaningful name to identify the performer in logs and for debugging.
    # @return [String] The queues from which Jobs are worked
    def name
      @queue_string
    end

    # Perform the next eligible job
    # @return [Object, nil] Returns job result or +nil+ if no job was found
    def next
      job_query.perform_with_advisory_lock
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
      @_job_query ||= GoodJob::Execution.queue_string(queue_string)
    end

    def parsed_queues
      @_parsed_queues ||= GoodJob::Execution.queue_parser(queue_string)
    end
  end
end
