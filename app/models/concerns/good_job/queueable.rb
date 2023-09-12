# frozen_string_literal: true

module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module Queueable
    extend ActiveSupport::Concern

    # Raised if something attempts to execute a previously completed Execution again.
    PreviouslyPerformedError = Class.new(StandardError)

    # String separating Error Class from Error Message
    ERROR_MESSAGE_SEPARATOR = ": "

    module ClassMethods
      # Parse a string representing a group of queues into a more readable data
      # structure.
      # @param string [String] Queue string
      # @return [Hash]
      #   How to match a given queue. It can have the following keys and values:
      #   - +{ all: true }+ indicates that all queues match.
      #   - +{ exclude: Array<String> }+ indicates the listed queue names should
      #     not match.
      #   - +{ include: Array<String> }+ indicates the listed queue names should
      #     match.
      #   - +{ include: Array<String>, ordered_queues: true }+ indicates the listed
      #     queue names should match, and dequeue should respect queue order.
      # @example
      #   GoodJob::Execution.queue_parser('-queue1,queue2')
      #   => { exclude: [ 'queue1', 'queue2' ] }
      def queue_parser(string)
        string = string.presence || '*'

        case string.first
        when '-'
          exclude_queues = true
          string = string[1..]
        when '+'
          ordered_queues = true
          string = string[1..]
        end

        queues = string.split(',').map(&:strip)

        if queues.include?('*')
          { all: true }
        elsif exclude_queues
          { exclude: queues }
        elsif ordered_queues
          {
            include: queues,
            ordered_queues: true,
          }
        else
          { include: queues }
        end
      end

      # Fetches the scheduled execution time of the next eligible Execution(s).
      # @param after [DateTime]
      # @param limit [Integer]
      # @param now_limit [Integer, nil]
      # @return [Array<DateTime>]
      def next_scheduled_at(after: nil, limit: 100, now_limit: nil)
        query = advisory_unlocked.unfinished.schedule_ordered

        after ||= Time.current
        after_query = query.where('scheduled_at > ?', after).or query.where(scheduled_at: nil).where('created_at > ?', after)
        after_at = after_query.limit(limit).pluck(:scheduled_at, :created_at).map { |timestamps| timestamps.compact.first }

        if now_limit&.positive?
          now_query = query.where('scheduled_at < ?', Time.current).or query.where(scheduled_at: nil)
          now_at = now_query.limit(now_limit).pluck(:scheduled_at, :created_at).map { |timestamps| timestamps.compact.first }
        end

        Array(now_at) + after_at
      end

      def format_error(error)
        raise ArgumentError unless error.is_a?(Exception)

        [error.class.to_s, ERROR_MESSAGE_SEPARATOR, error.message].join
      end
    end

    included do
      define_model_callbacks :perform
      define_model_callbacks :perform_unlocked, only: :after

      set_callback :perform, :around, :reset_batch_values
      set_callback :perform_unlocked, :after, :continue_discard_or_finish_batch

      # Get executions that have not yet finished (succeeded or discarded).
      # @!method unfinished
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :unfinished, -> { where(finished_at: nil) }

      # Get executions that are not scheduled for a later time than now (i.e. jobs that
      # are not scheduled or scheduled for earlier than the current time).
      # @!method only_scheduled
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(Time.current)).or(where(scheduled_at: nil)) }

      # Order executions by priority (highest priority first).
      # @!method priority_ordered
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :priority_ordered, (lambda do
        if GoodJob.configuration.smaller_number_is_higher_priority
          order('priority ASC NULLS LAST')
        else
          order('priority DESC NULLS LAST')
        end
      end)

      # Order executions by created_at, for first-in first-out
      # @!method creation_ordered
      # @!scope class
      # @return [ActiveRecord:Relation]
      scope :creation_ordered, -> { order(created_at: :asc) }

      # Order executions for de-queueing
      # @!method dequeueing_ordered(parsed_queues)
      # @!scope class
      # @param parsed_queues [Hash]
      #   optional output of .queue_parser, parsed queues, will be used for
      #   ordered queues.
      # @return [ActiveRecord::Relation]
      scope :dequeueing_ordered, (lambda do |parsed_queues|
        relation = self
        relation = relation.queue_ordered(parsed_queues[:include]) if parsed_queues && parsed_queues[:ordered_queues] && parsed_queues[:include]
        relation = relation.priority_ordered.creation_ordered

        relation
      end)

      # Order executions in order of queues in array param
      # @!method queue_ordered(queues)
      # @!scope class
      # @param queues [Array<string] ordered names of queues
      # @return [ActiveRecord::Relation]
      scope :queue_ordered, (lambda do |queues|
        clauses = queues.map.with_index do |queue_name, index|
          "WHEN queue_name = '#{queue_name}' THEN #{index}"
        end

        order(
          Arel.sql("(CASE #{clauses.join(' ')} ELSE #{queues.length} END)")
        )
      end)

      # Order jobs by scheduled or created (oldest first).
      # @!method schedule_ordered
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :schedule_ordered, -> { order(coalesce_scheduled_at_created_at.asc) }

      # Get Jobs on queues that match the given queue string.
      # @!method queue_string(string)
      # @!scope class
      # @param string [String]
      #   A string expression describing what queues to select. See
      #   {Execution.queue_parser} or
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
    end

    # Execute the ActiveJob job this {Execution} represents.
    # @return [ExecutionResult]
    #   An array of the return value of the job's +#perform+ method and the
    #   exception raised by the job, if any. If the job completed successfully,
    #   the second array entry (the exception) will be +nil+ and vice versa.
    def perform(id_for_lock: nil)
      run_callbacks(:perform) do
        raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

        discrete_execution = nil
        result = GoodJob::CurrentThread.within do |current_thread|
          current_thread.reset
          current_thread.execution = self

          if performed_at
            current_thread.execution_interrupted = performed_at

            if discrete?
              interrupt_error_string = self.class.format_error(GoodJob::InterruptError.new("Interrupted after starting perform at '#{performed_at}'"))
              self.error = interrupt_error_string
              self.error_event = GoodJob::ErrorEvents::ERROR_EVENT_INTERRUPTED if self.class.error_event_migrated?

              discrete_execution_attrs = {
                error: interrupt_error_string,
                finished_at: Time.current,
              }
              discrete_execution_attrs[:error_event] = GoodJob::ErrorEvents::ERROR_EVENT_ENUMS[GoodJob::ErrorEvents::ERROR_EVENT_INTERRUPTED] if self.class.error_event_migrated?
              discrete_executions.where(finished_at: nil).where.not(performed_at: nil).update_all(discrete_execution_attrs) # rubocop:disable Rails/SkipsModelValidations
            end
          end

          if discrete?
            transaction do
              now = Time.current
              discrete_execution = discrete_executions.create!({
                job_class: job_class,
                queue_name: queue_name,
                serialized_params: serialized_params,
                scheduled_at: (scheduled_at || created_at),
                created_at: now,
              }.tap do |args|
                args[:process_id] = id_for_lock if id_for_lock && self.class.process_lock_migrated?
              end)

              assign_attributes(locked_by_id: id_for_lock, locked_at: now) if id_for_lock && locked_by_id.blank? && self.class.process_lock_migrated?
              update!(performed_at: now, executions_count: ((self[:executions_count] || 0) + 1))
            end
          else
            now = Time.current
            assign_attributes(locked_by_id: id_for_lock, locked_at: now) if id_for_lock && self.class.process_lock_migrated?
            update!(performed_at: now)
          end

          ActiveSupport::Notifications.instrument("perform_job.good_job", { execution: self, process_id: current_thread.process_id, thread_name: current_thread.thread_name }) do |instrument_payload|
            value = ActiveJob::Base.execute(active_job_data)

            if value.is_a?(Exception)
              handled_error = value
              value = nil
            end
            handled_error ||= current_thread.error_on_retry || current_thread.error_on_discard

            error_event = if handled_error == current_thread.error_on_discard
                            GoodJob::ErrorEvents::ERROR_EVENT_DISCARDED
                          elsif handled_error == current_thread.error_on_retry
                            GoodJob::ErrorEvents::ERROR_EVENT_RETRIED
                          elsif handled_error == current_thread.error_on_retry_stopped
                            GoodJob::ErrorEvents::ERROR_EVENT_RETRY_STOPPED
                          elsif handled_error
                            GoodJob::ErrorEvents::ERROR_EVENT_HANDLED
                          end

            instrument_payload.merge!(
              value: value,
              handled_error: handled_error,
              retried: current_thread.execution_retried,
              error_event: error_event
            )
            ExecutionResult.new(value: value, handled_error: handled_error, error_event: error_event, retried: current_thread.execution_retried)
          rescue StandardError => e
            error_event = if e.is_a?(GoodJob::InterruptError)
                            GoodJob::ErrorEvents::ERROR_EVENT_INTERRUPTED
                          elsif e == current_thread.error_on_retry_stopped
                            GoodJob::ErrorEvents::ERROR_EVENT_RETRY_STOPPED
                          else
                            GoodJob::ErrorEvents::ERROR_EVENT_UNHANDLED
                          end

            instrument_payload[:unhandled_error] = e
            ExecutionResult.new(value: nil, unhandled_error: e, error_event: error_event)
          end
        end

        job_error = result.handled_error || result.unhandled_error
        if job_error
          error_string = self.class.format_error(job_error)
          self.error = error_string
          self.error_event = result.error_event if self.class.error_event_migrated?
          if discrete_execution
            discrete_execution.error = error_string
            discrete_execution.error_event = result.error_event if discrete_execution.class.error_event_migrated?
          end
        else
          self.error = nil
          self.error_event = nil if self.class.error_event_migrated?
        end
        reenqueued = result.retried? || retried_good_job_id.present?

        if self.class.process_lock_migrated?
          self.locked_by_id = nil
          self.locked_at = nil
        end

        if result.unhandled_error && GoodJob.retry_on_unhandled_error
          if discrete_execution
            transaction do
              discrete_execution.update!(finished_at: Time.current)
              update!(performed_at: nil, finished_at: nil, retried_good_job_id: nil)
            end
          else
            save!
          end
        elsif GoodJob.preserve_job_records == true || reenqueued || (result.unhandled_error && GoodJob.preserve_job_records == :on_unhandled_error) || cron_key.present?
          now = Time.current
          if discrete_execution
            if reenqueued
              self.performed_at = nil
            else
              self.finished_at = now
            end
            discrete_execution.finished_at = now
            transaction do
              discrete_execution.save!
              save!
            end
          else
            self.finished_at = now
            save!
          end
        else
          destroy_job
        end

        result
      end
    end

    # Destroys this execution and all executions within the same job
    def destroy_job
      @_destroy_job = true
      destroy!
    ensure
      @_destroy_job = false
    end

    private

    def reset_batch_values(&block)
      GoodJob::Batch.within_thread(batch_id: nil, batch_callback_id: nil, &block)
    end

    def continue_discard_or_finish_batch
      batch._continue_discard_or_finish(self) if GoodJob::BatchRecord.migrated? && batch.present?
    end
  end
end
