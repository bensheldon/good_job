# frozen_string_literal: true

module GoodJob
  # NOTE: This class delegates to {GoodJob::BatchRecord} and is intended to be the public interface for Batches.
  class Batch
    include GlobalID::Identification

    thread_cattr_accessor :current_batch_id
    thread_cattr_accessor :current_batch_callback_id

    PROTECTED_PROPERTIES = %i[
      on_finish
      on_success
      on_discard
      callback_queue_name
      callback_priority
      description
      properties
    ].freeze

    delegate(
      :id,
      :created_at,
      :updated_at,
      :persisted?,
      :enqueued_at,
      :finished_at,
      :discarded_at,
      :jobs_finished_at,
      :enqueued?,
      :finished?,
      :succeeded?,
      :discarded?,
      :jobs_finished?,
      :description,
      :description=,
      :on_finish,
      :on_finish=,
      :on_success,
      :on_success=,
      :on_discard,
      :on_discard=,
      :callback_queue_name,
      :callback_queue_name=,
      :callback_priority,
      :callback_priority=,
      :properties,
      :properties=,
      :save,
      :reload,
      to: :record
    )

    # Create a new batch and enqueue it
    # @param properties [Hash] Additional properties to be stored on the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [GoodJob::BatchRecord]
    def self.enqueue(active_jobs = [], **properties, &block)
      new.tap do |batch|
        batch.enqueue(active_jobs, **properties, &block)
      end
    end

    # Bulk-enqueue multiple batches with their jobs in minimal DB round-trips.
    #
    # Instead of creating batches one-at-a-time (~7 queries per batch), this method
    # inserts all batch records and jobs in a fixed number of queries:
    #   1. INSERT all BatchRecords  (insert_all!)
    #   2. INSERT all Jobs          (insert_all)
    #   3. NOTIFY per distinct queue/scheduled_at
    #
    # @param batch_job_pairs [Array<Array(GoodJob::Batch, Array<ActiveJob::Base>)>]
    #   Array of [batch, jobs] pairs. Each batch must be new (not yet persisted).
    # @return [Array<GoodJob::Batch>] The enqueued batches
    # @raise [ArgumentError] if any batch is already persisted
    def self.enqueue_all(batch_job_pairs)
      batch_job_pairs = Array(batch_job_pairs)
      return [] if batch_job_pairs.empty?

      batch_job_pairs.each do |(batch, _)|
        raise ArgumentError, "All batches must be new (not persisted)" if batch.persisted?
      end

      Rails.application.executor.wrap do
        current_time = Time.current
        adapter = ActiveJob::Base.queue_adapter
        execute_inline = adapter.respond_to?(:execute_inline?) && adapter.execute_inline?

        # Phase 1: Insert all batch records
        batch_rows = _build_batch_rows(batch_job_pairs, current_time)
        BatchRecord.insert_all!(batch_rows) # rubocop:disable Rails/SkipsModelValidations
        _mark_batches_persisted(batch_job_pairs, batch_rows, current_time)

        # Phase 2: Build and partition jobs by concurrency limits
        build_result = _build_and_partition_jobs(batch_job_pairs, current_time)

        # Phase 3–6: Insert, claim, and execute inline jobs
        lock_strategy = Job.effective_lock_strategy
        tracker_registered = false
        lock_id = nil
        persisted_jobs = []
        inline_jobs = []

        if execute_inline
          GoodJob.capsule.tracker.register
          tracker_registered = true
          lock_id = GoodJob.capsule.tracker.id_for_lock
        end

        begin
          if build_result[:bulkable].any?
            Job.transaction(requires_new: true, joinable: false) do
              persisted_jobs = _insert_jobs(build_result[:bulkable], build_result[:active_jobs_by_job_id])

              if execute_inline
                inline_jobs = persisted_jobs.select { |job| job.scheduled_at.nil? || job.scheduled_at <= current_time }
                if lock_strategy != :advisory && lock_id && inline_jobs.any?
                  Job.where(id: inline_jobs.map(&:id)).update_all( # rubocop:disable Rails/SkipsModelValidations
                    locked_by_id: lock_id, locked_at: current_time, lock_type: Job.lock_types[lock_strategy.to_s]
                  )
                  inline_jobs.each { |j| j.assign_attributes(locked_by_id: lock_id, locked_at: current_time, lock_type: lock_strategy) }
                end
                case lock_strategy
                when :advisory, :hybrid
                  inline_jobs.each(&:advisory_lock!)
                end
              end
            end
          end

          # Phase 4: Handle empty batches — they need _continue_discard_or_finish
          # to trigger on_success/on_finish callbacks (batch_record.rb:77).
          batches_with_jobs = Set.new
          build_result[:bulkable].each { |entry| batches_with_jobs.add(entry[:batch]) }
          build_result[:unbulkable].each { |entry| batches_with_jobs.add(entry[:batch]) }

          empty_batches = batch_job_pairs.map(&:first).reject { |batch| batches_with_jobs.include?(batch) }
          if empty_batches.any?
            buffer = GoodJob::Adapter::InlineBuffer.capture do
              empty_batches.each do |batch|
                batch._record.reload
                batch._record._continue_discard_or_finish(lock: true)
              end
            end
            buffer.call
          end

          # Phase 5: Enqueue concurrency-limited jobs individually
          build_result[:unbulkable].each do |entry|
            within_thread(batch_id: entry[:batch].id) do
              entry[:active_job].enqueue
            end
          rescue GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError
            # ignore — matches Bulk::Buffer behavior (bulk.rb:107-109)
          end

          # Phase 6: Execute inline jobs
          if inline_jobs.any?
            deferred = GoodJob::Adapter::InlineBuffer.defer?
            GoodJob::Adapter::InlineBuffer.perform_now_or_defer do
              until inline_jobs.empty?
                inline_job = inline_jobs.shift
                active_job = build_result[:active_jobs_by_job_id][inline_job.active_job_id]
                adapter.send(:perform_inline, inline_job, notify: deferred ? adapter.send(:send_notify?, active_job) : false, already_claimed: lock_strategy != :advisory, advisory_unlock: lock_strategy != :skiplocked)
              end
            ensure
              inline_jobs.each(&:advisory_unlock)
              GoodJob.capsule.tracker.unregister if tracker_registered
              tracker_registered = false
            end
          elsif tracker_registered
            GoodJob.capsule.tracker.unregister
            tracker_registered = false
          end
        rescue StandardError
          if tracker_registered
            GoodJob.capsule.tracker.unregister
            tracker_registered = false
          end
          raise
        end

        # Phase 7: Send NOTIFY for non-inline jobs
        non_inline_jobs = persisted_jobs - inline_jobs
        non_inline_jobs = non_inline_jobs.reject(&:finished_at) if inline_jobs.any?
        _send_notifications(non_inline_jobs, build_result[:active_jobs_by_job_id], adapter) if non_inline_jobs.any?

        batch_job_pairs.map(&:first)
      end
    end

    def self.primary_key
      :id
    end

    def self.find(id)
      new _record: BatchRecord.find(id)
    end

    # Helper method to enqueue jobs and assign them to a batch
    def self.within_thread(batch_id: nil, batch_callback_id: nil)
      original_batch_id = current_batch_id
      original_batch_callback_id = current_batch_callback_id

      self.current_batch_id = batch_id
      self.current_batch_callback_id = batch_callback_id

      yield
    ensure
      self.current_batch_id = original_batch_id
      self.current_batch_callback_id = original_batch_callback_id
    end

    def initialize(_record: nil, **properties) # rubocop:disable Lint/UnderscorePrefixedVariableName
      self.record = _record || BatchRecord.new
      assign_properties(properties)
    end

    # @return [Array<ActiveJob::Base>] Active jobs added to the batch
    def enqueue(active_jobs = [], **properties, &block)
      assign_properties(properties)
      if record.new_record?
        record.save!
      else
        record.transaction do
          record.with_advisory_lock(function: "pg_advisory_xact_lock") do
            record.enqueued_at_will_change!
            record.jobs_finished_at_will_change! if GoodJob::BatchRecord.jobs_finished_at_migrated?
            record.finished_at_will_change!

            update_attributes = { discarded_at: nil, finished_at: nil }
            update_attributes[:jobs_finished_at] = nil if GoodJob::BatchRecord.jobs_finished_at_migrated?
            record.update!(**update_attributes)
          end
        end
      end

      active_jobs = add(active_jobs, &block)

      Rails.application.executor.wrap do
        buffer = GoodJob::Adapter::InlineBuffer.capture do
          record.transaction do
            record.with_advisory_lock(function: "pg_advisory_xact_lock") do
              record.update!(enqueued_at: Time.current)

              # During inline execution, this could enqueue and execute further jobs
              record._continue_discard_or_finish(lock: false)
            end
          end
        end
        buffer.call
      end

      active_jobs
    end

    # Enqueue jobs and add them to the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [Array<ActiveJob::Base>] Active jobs added to the batch
    def add(active_jobs = nil, &block)
      record.save if record.new_record?

      buffer = Bulk::Buffer.new
      buffer.add(active_jobs)
      buffer.capture(&block) if block

      self.class.within_thread(batch_id: id) do
        buffer.enqueue
      end

      buffer.active_jobs
    end

    def retry
      Rails.application.executor.wrap do
        buffer = GoodJob::Adapter::InlineBuffer.capture do
          record.transaction do
            record.with_advisory_lock(function: "pg_advisory_xact_lock") do
              update_attributes = { discarded_at: nil, finished_at: nil }
              update_attributes[:jobs_finished_at] = nil if GoodJob::BatchRecord.jobs_finished_at_migrated?
              record.update!(update_attributes)

              discarded_jobs = record.jobs.discarded
              Job.defer_after_commit_maybe(discarded_jobs) do
                discarded_jobs.each(&:retry_job)
                record._continue_discard_or_finish(lock: false)
              end
            end
          end
        end
        buffer.call
      end
    end

    def active_jobs
      record.jobs.map(&:active_job)
    end

    def callback_active_jobs
      record.callback_jobs.map(&:active_job)
    end

    def assign_properties(properties)
      properties = properties.dup
      batch_attrs = PROTECTED_PROPERTIES.index_with { |key| properties.delete(key) }.compact
      record.assign_attributes(batch_attrs)
      self.properties.merge!(properties)
    end

    def _record
      record
    end

    # @!visibility private
    def self._build_batch_rows(batch_job_pairs, current_time)
      batch_job_pairs.map do |batch, _jobs|
        record = batch._record
        {
          id: SecureRandom.uuid,
          created_at: current_time,
          updated_at: current_time,
          enqueued_at: current_time,
          on_finish: record.on_finish,
          on_success: record.on_success,
          on_discard: record.on_discard,
          callback_queue_name: record.callback_queue_name,
          callback_priority: record.callback_priority,
          description: record.description,
          # record.serialized_properties returns the internally-stored form
          # which already includes _aj_symbol_keys metadata from
          # PropertySerializer.dump. Pass it directly — insert_all! handles
          # jsonb encoding, and PropertySerializer.load will deserialize
          # correctly on read.
          serialized_properties: record.serialized_properties || {},
        }
      end
    end

    # @!visibility private
    def self._mark_batches_persisted(batch_job_pairs, batch_rows, current_time)
      batch_job_pairs.each_with_index do |(batch, _jobs), index|
        record = batch._record
        record.id = batch_rows[index][:id]
        record.created_at = current_time
        record.updated_at = current_time
        record.enqueued_at = current_time
        record.instance_variable_set(:@new_record, false)
      end
    end

    # @!visibility private
    def self._build_and_partition_jobs(batch_job_pairs, current_time)
      bulkable = []
      unbulkable = []
      active_jobs_by_job_id = {}

      batch_job_pairs.each do |batch, jobs|
        next if jobs.blank?

        jobs.each do |active_job|
          active_jobs_by_job_id[active_job.job_id] = active_job

          # Jobs with concurrency limits must be enqueued individually so the
          # before_enqueue concurrency check runs. Mirrors Bulk::Buffer#enqueue
          # partitioning (bulk.rb:95-98).
          if active_job.respond_to?(:good_job_concurrency_key) &&
             active_job.good_job_concurrency_key.present? &&
             (active_job.class.good_job_concurrency_config[:enqueue_limit] ||
               active_job.class.good_job_concurrency_config[:total_limit])
            unbulkable << { batch: batch, active_job: active_job }
          else
            good_job = Job.build_for_enqueue(active_job)

            # Normalize timestamps (mirrors Adapter#enqueue_all, adapter.rb:62-65)
            good_job.scheduled_at = current_time if good_job.scheduled_at == good_job.created_at
            good_job.created_at = current_time
            good_job.updated_at = current_time

            # Set batch_id directly — can't use thread-local for multi-batch bulk
            good_job.batch_id = batch.id
            good_job.batch_callback_id = nil

            bulkable << { batch: batch, active_job: active_job, good_job: good_job }
          end
        end
      end

      { bulkable: bulkable, unbulkable: unbulkable, active_jobs_by_job_id: active_jobs_by_job_id }
    end

    # @!visibility private
    def self._insert_jobs(bulkable_entries, active_jobs_by_job_id)
      column_names = Job.column_names
      job_attributes = bulkable_entries.map { |entry| entry[:good_job].attributes.slice(*column_names) }
      results = Job.insert_all(job_attributes, returning: %w[id active_job_id]) # rubocop:disable Rails/SkipsModelValidations

      job_id_map = results.to_h { |row| [row['active_job_id'], row['id']] }

      # Set provider_job_id on ActiveJob instances (mirrors adapter.rb:74-76)
      active_jobs_by_job_id.each_value do |active_job|
        active_job.provider_job_id = job_id_map[active_job.job_id]
        active_job.successfully_enqueued = active_job.provider_job_id.present? if active_job.respond_to?(:successfully_enqueued=)
      end

      # Mark Job AR objects as persisted (mirrors adapter.rb:78-80)
      bulkable_entries.each do |entry|
        entry[:good_job].instance_variable_set(:@new_record, false) if job_id_map[entry[:good_job].active_job_id]
      end

      bulkable_entries.pluck(:good_job).select(&:persisted?)
    end

    # @!visibility private
    def self._send_notifications(jobs, active_jobs_by_job_id, adapter)
      return unless GoodJob.configuration.enable_listen_notify

      jobs.group_by(&:queue_name).each do |queue_name, jobs_by_queue|
        jobs_by_queue.group_by(&:scheduled_at).each do |scheduled_at, grouped_jobs|
          state = { queue_name: queue_name, count: grouped_jobs.size }
          state[:scheduled_at] = scheduled_at if scheduled_at

          executed_locally = adapter.respond_to?(:execute_async?) && adapter.execute_async? && GoodJob.capsule&.create_thread(state)
          unless executed_locally
            state[:count] = grouped_jobs.count { |job| _send_notify?(active_jobs_by_job_id[job.active_job_id]) }
            Notifier.notify(state) unless state[:count].zero?
          end
        end
      end
    end

    # Mirrors Adapter#send_notify? (adapter.rb:242-247)
    # @!visibility private
    def self._send_notify?(active_job)
      return true unless active_job.respond_to?(:good_job_notify)

      !(active_job.good_job_notify == false ||
        (active_job.class.good_job_notify == false && active_job.good_job_notify.nil?))
    end

    private

    attr_accessor :record
  end
end

ActiveSupport.run_load_hooks(:good_job_batch, GoodJob::Batch)
