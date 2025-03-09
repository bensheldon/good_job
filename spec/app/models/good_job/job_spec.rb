# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Job do
  let(:active_job_id) { SecureRandom.uuid }

  let(:job) do
    described_class.create!(
      id: active_job_id,
      active_job_id: active_job_id,
      scheduled_at: 10.minutes.from_now,
      queue_name: 'mice',
      priority: 10,
      job_class: "TestJob",
      serialized_params: {
        'job_id' => active_job_id,
        'job_class' => 'TestJob',
        'executions' => 1,
        'exception_executions' => { 'TestJob::Error' => 1 },
        'queue_name' => 'mice',
        'priority' => 10,
        'arguments' => ['cat', { 'canine' => 'dog' }],
      }
    ).tap do |job|
      job.executions.create!(
        scheduled_at: 1.minute.ago,
        created_at: 1.minute.ago,
        finished_at: 1.minute.ago,
        duration: 60.seconds,
        error: "TestJob::Error: TestJob::Error"
      )
    end
  end

  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform(*)
        raise TestJob::RunError, "Ran this job"
      end
    end)
    stub_const 'TestJob::RunError', Class.new(StandardError)
    stub_const 'TestJob::Error', Class.new(StandardError)
  end

  describe '#id' do
    it 'is the ActiveJob ID' do
      expect(job.id).to eq job.active_job_id
    end
  end

  describe 'implicit sort order' do
    it 'is by created_at' do
      first_job = described_class.create(active_job_id: '67160140-1bec-4c3b-bc34-1a8b36f87b21')
      described_class.create(active_job_id: '3732d706-fd5a-4c39-b1a5-a9bc6d265811')
      last_job = described_class.create(active_job_id: '4fbae77c-6f22-488f-ad42-5bd20f39c28c')

      result = described_class.all

      expect(result.first).to eq first_job
      expect(result.last).to eq last_job
    end
  end

  describe '#running?' do
    context 'when advisory_locks are NOT eagerloaded' do
      it 'is true if the job is Advisory Locked' do
        job.with_advisory_lock do
          expect(job).to be_running
        end
      end
    end

    context 'when advisory_locks are eagerloaded' do
      it 'is true if the job is Advisory Locked' do
        job.with_advisory_lock do
          eagerloaded_job = described_class.where(active_job_id: job.id).includes_advisory_locks.first
          expect(eagerloaded_job).to be_running
        end
      end
    end

    it 'is true if the job is Advisory Locked' do
      job.with_advisory_lock do
        job_with_locktype = described_class.where(active_job_id: job.id).includes_advisory_locks.first
        expect(job_with_locktype).to be_running
      end
    end
  end

  describe '#finished?' do
    it 'is true if the job has finished' do
      expect do
        job.update(finished_at: Time.current)
      end.to change(job, :finished?).from(false).to(true)
    end
  end

  describe '#succeeded?' do
    it 'is true if the job has finished without error' do
      expect do
        job.update(finished_at: Time.current, error: nil)
      end.to change(job, :succeeded?).from(false).to(true)

      expect do
        job.update(finished_at: Time.current, error: 'TestJob::Error: TestJob::Error')
      end.to change(job, :succeeded?).from(true).to(false)
    end
  end

  describe '#discarded?' do
    it 'is true if the job has finished with an error' do
      expect do
        job.update(finished_at: Time.current, error: 'TestJob::Error: TestJob::Error')
      end.to change(job, :discarded?).from(false).to(true)

      expect do
        job.update(finished_at: Time.current, error: nil)
      end.to change(job, :discarded?).from(true).to(false)
    end
  end

  describe '#retry_job' do
    context 'when job is retried' do
      before do
        job.update!(
          finished_at: Time.current,
          error: "TestJob::Error: TestJob::Error"
        )
      end

      it 'updates the original job' do
        expect do
          job.retry_job
        end.to change { job.reload.finished? }.from(true).to(false)
        expect(job.executions.count).to eq 1

        expect(job).to have_attributes(
          error: "TestJob::Error: TestJob::Error",
          error_event: "retried"
        )
      end

      context 'when run inline' do
        before do
          stub_const "TestJob", (Class.new(ActiveJob::Base) do
            retry_on TestJob::Error, wait: 0

            def perform(*)
              raise TestJob::Error if executions < 4
            end
          end)
          stub_const "TestJob::Error", Class.new(StandardError)
        end

        it 'executes the job' do
          TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
          job.retry_job

          expect(job).to be_finished

          executions = job.executions.order(created_at: :asc).to_a
          expect(executions.size).to eq 3 # initial execution isn't created in test
          expect(executions.map(&:error)).to eq ["TestJob::Error: TestJob::Error", "TestJob::Error: TestJob::Error", nil]
          expect(executions[0].finished_at).to be < executions[1].finished_at
          expect(executions[1].finished_at).to be < executions[2].finished_at
        end
      end
    end

    context 'when job is already locked' do
      it 'raises an Error' do
        job.with_advisory_lock do
          expect do
            rails_promise(job, &:retry_job).value!
          end.to raise_error GoodJob::AdvisoryLockable::RecordAlreadyAdvisoryLockedError
        end
      end
    end

    context 'when job is not discarded' do
      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).not_to eq :discarded
        expect { job.retry_job }.to raise_error GoodJob::Job::ActionForStateMismatchError
      end
    end

    context 'when job arguments cannot be deserialized' do
      let(:deserialization_exception) do
        # `ActiveJob::DeserializationError` looks at `$!` (last exception), so to create
        # an instance of this exception we need to trigger a canary exception first.
        original_exception = StandardError.new("Unsupported argument")
        begin
          raise original_exception
        rescue StandardError
          ActiveJob::DeserializationError.new
        end
      end

      before do
        job.update!(
          finished_at: Time.current,
          error: "TestJob::Error: TestJob::Error"
        )
      end

      it 'ignores the error and discards the job' do
        allow_any_instance_of(ActiveJob::Base).to receive(:deserialize_arguments_if_needed).and_raise(deserialization_exception)
        expect_any_instance_of(ActiveJob::Base).to receive(:deserialize_arguments_if_needed)

        expect do
          job.retry_job
        end.to change { job.reload.status }.from(:discarded).to(:queued)
      end
    end
  end

  describe '#discard_job' do
    context 'when a job is unfinished' do
      it 'discards the job with a DiscardJobError' do
        expect do
          job.discard_job("Discarded in test")
        end.to change { job.reload.status }.from(:scheduled).to(:discarded)

        expect(job.reload).to have_attributes(
          error: "GoodJob::Job::DiscardJobError: Discarded in test",
          error_event: "discarded",
          finished_at: within(1.second).of(Time.current)
        )
      end
    end

    context 'when a job is not in scheduled/queued state' do
      before do
        job.update! finished_at: Time.current
      end

      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).to eq :succeeded
        expect { job.discard_job("Discard in test") }.to raise_error GoodJob::Job::ActionForStateMismatchError
      end
    end

    context 'when job arguments cannot be deserialized' do
      let(:deserialization_exception) do
        # `ActiveJob::DeserializationError` looks at `$!` (last exception), so to create
        # an instance of this exception we need to trigger a canary exception first.
        original_exception = StandardError.new("Unsupported argument")
        begin
          raise original_exception
        rescue StandardError
          ActiveJob::DeserializationError.new
        end
      end

      it 'ignores the error and discards the job' do
        allow_any_instance_of(ActiveJob::Base).to receive(:deserialize_arguments_if_needed).and_raise(deserialization_exception)
        expect_any_instance_of(ActiveJob::Base).to receive(:deserialize_arguments_if_needed)

        expect do
          job.discard_job("Discarded in test")
        end.to change { job.reload.status }.from(:scheduled).to(:discarded)
      end
    end

    context 'when job class does not exist' do
      before do
        job.update!(serialized_params: { 'job_class' => 'NonexistentJob' })
      end

      it 'ignores the error and discards the job' do
        expect do
          job.discard_job("Discarded in test")
        end.to change { job.reload.status }.from(:scheduled).to(:discarded)
      end
    end
  end

  describe '#force_discard_job' do
    it 'discards the job even when advisory locked' do
      locked_event = Concurrent::Event.new
      done_event = Concurrent::Event.new

      promise = Concurrent::Promises.future do
        rails_promise do
          # pretend the job is running
          job.with_advisory_lock do
            locked_event.set
            done_event.wait(10)
          end
        end
      end
      locked_event.wait(10)

      job.force_discard_job("Discarded in test")
      job.reload
      expect(job.finished_at).to be_present
      expect(job.error).to eq "GoodJob::Job::DiscardJobError: Discarded in test"
    ensure
      locked_event.set
      done_event.set
      promise.value!
    end
  end

  describe '#reschedule_job' do
    context 'when a job is scheduled' do
      it 'reschedules the job to right now by default' do
        expect do
          job.reschedule_job
        end.to change { job.reload.status }.from(:scheduled).to(:queued)

        expect(job.reload).to have_attributes(
          scheduled_at: within(1.second).of(Time.current)
        )
      end
    end

    context 'when a job is not in scheduled/queued state' do
      before do
        job.update! finished_at: Time.current
      end

      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).to eq :succeeded
        expect { job.reschedule_job }.to raise_error GoodJob::Job::ActionForStateMismatchError
      end
    end
  end

  describe '#destroy_job' do
    it 'destroys job and executions' do
      job.update! finished_at: Time.current
      job.destroy_job

      expect { job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect(GoodJob::Execution.count).to eq 0
    end

    context 'when a job is not finished' do
      it 'raises an ActionForStateMismatchError' do
        expect { job.destroy_job }.to raise_error GoodJob::Job::ActionForStateMismatchError
      end
    end
  end

  describe "behavior adopted from v3 Execution" do
    let(:process_id) { SecureRandom.uuid }

    around do |example|
      Rails.application.executor.wrap { example.run }
    end

    before do
      stub_const "RUN_JOBS", Concurrent::Array.new
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        self.queue_name = 'test'
        self.priority = 50

        def perform(result_value = nil, raise_error: false)
          RUN_JOBS << provider_job_id
          raise TestJob::ExpectedError, "Raised expected error" if raise_error

          result_value
        end
      end)
      stub_const 'TestJob::ExpectedError', Class.new(StandardError)
    end

    describe 'implicit sort order' do
      it 'is by created at' do
        first_job = described_class.create(active_job_id: '67160140-1bec-4c3b-bc34-1a8b36f87b21')
        described_class.create(active_job_id: '3732d706-fd5a-4c39-b1a5-a9bc6d265811')
        last_job = described_class.create(active_job_id: '4fbae77c-6f22-488f-ad42-5bd20f39c28c')

        result = described_class.all

        expect(result.first).to eq first_job
        expect(result.last).to eq last_job
      end
    end

    describe '.enqueue' do
      let(:active_job) { TestJob.new }

      it 'assigns id, scheduled_at' do
        expect { described_class.enqueue(active_job) }.to change(described_class, :count).by(1)

        job = described_class.last
        expect(job).to have_attributes(
          id: active_job.job_id,
          active_job_id: active_job.job_id,
          created_at: within(1.second).of(Time.current),
          scheduled_at: job.created_at
        )
      end

      it 'creates a new GoodJob record' do
        job = nil

        expect do
          job = described_class.enqueue(active_job)
        end.to change(described_class, :count).by(1)

        expect(job).to have_attributes(
          active_job_id: job.id,
          serialized_params: a_kind_of(Hash),
          queue_name: 'test',
          priority: 50,
          scheduled_at: job.created_at
        )
      end

      it 'is schedulable' do
        execution = described_class.enqueue(active_job, scheduled_at: 1.day.from_now)
        expect(execution).to have_attributes(
          scheduled_at: within(1.second).of(1.day.from_now)
        )
      end

      it 'can be created with an advisory lock' do
        unlocked_execution = described_class.enqueue(TestJob.new)
        expect(unlocked_execution.advisory_locked?).to be false

        locked_execution = described_class.enqueue(TestJob.new, create_with_advisory_lock: true)
        expect(locked_execution.advisory_locked?).to be true

        locked_execution.advisory_unlock
      end
    end

    describe '.perform_with_advisory_lock' do
      context 'with one job' do
        let(:active_job) { TestJob.new('a string') }
        let!(:good_job) { described_class.enqueue(active_job) }

        it 'performs one job' do
          good_job_2 = described_class.create!(active_job_id: SecureRandom.uuid, serialized_params: {})

          described_class.perform_with_advisory_lock(lock_id: process_id)

          expect(good_job.reload.finished_at).to be_present
          expect(good_job_2.reload.finished_at).to be_blank
        end

        it 'returns the result or nil if not' do
          result = described_class.perform_with_advisory_lock(lock_id: process_id)

          expect(result).to be_a GoodJob::ExecutionResult
          expect(result.value).to eq 'a string'
          expect(result.unhandled_error).to be_nil

          described_class.enqueue(TestJob.new(true, raise_error: true))
          errored_result = described_class.all.perform_with_advisory_lock(lock_id: process_id)

          expect(result).to be_a GoodJob::ExecutionResult
          expect(errored_result.value).to be_nil
          expect(errored_result.unhandled_error).to be_an TestJob::ExpectedError
        end
      end

      context 'with multiple jobs' do
        def job_params
          {
            active_job_id: SecureRandom.uuid,
            queue_name: "default",
            priority: 0,
            job_class: "TestJob",
            scheduled_at: Time.current,
            serialized_params: { job_class: "TestJob" },
          }
        end

        let!(:older_job) { described_class.create!(job_params.merge(created_at: 10.minutes.ago)) }
        let!(:newer_job) { described_class.create!(job_params.merge(created_at: 5.minutes.ago)) }
        let!(:low_priority_job) { described_class.create!(job_params.merge(priority: 20)) }
        let!(:high_priority_job) { described_class.create!(job_params.merge(priority: -20)) }

        it "orders by priority ascending and creation descending" do
          4.times do
            described_class.perform_with_advisory_lock(lock_id: process_id)
          end
          expect(described_class.order(finished_at: :asc).to_a).to eq([
                                                                        high_priority_job,
                                                                        older_job,
                                                                        newer_job,
                                                                        low_priority_job,
                                                                      ])
        end
      end

      context "with multiple jobs and ordered queues" do
        def job_params
          { active_job_id: SecureRandom.uuid, scheduled_at: Time.current, queue_name: "default", priority: 0, serialized_params: { job_class: "TestJob" } }
        end

        let(:parsed_queues) { { include: %w{one two}, ordered_queues: true } }
        let!(:queue_two_job) { described_class.create!(job_params.merge(queue_name: "two", created_at: 10.minutes.ago, priority: 100)) }
        let!(:queue_one_job) { described_class.create!(job_params.merge(queue_name: "one", created_at: 1.minute.ago, priority: 1)) }

        it "orders by queue order" do
          described_class.perform_with_advisory_lock(lock_id: process_id, parsed_queues: parsed_queues) do |job|
            expect(job).to eq queue_one_job
          end
          described_class.perform_with_advisory_lock(lock_id: process_id, parsed_queues: parsed_queues) do |job|
            expect(job).to eq queue_two_job
          end
        end
      end
    end

    describe '.queue_parser' do
      it 'creates an intermediary hash' do
        result = described_class.queue_parser('first,second')
        expect(result).to eq({
                               include: %w[first second],
                             })

        result = described_class.queue_parser('-first,second')
        expect(result).to eq({
                               exclude: %w[first second],
                             })

        result = described_class.queue_parser('')
        expect(result).to eq({
                               all: true,
                             })
        result = described_class.queue_parser('+first,second')
        expect(result).to eq({
                               include: %w[first second],
          ordered_queues: true,
                             })
      end
    end

    describe '.queue_string' do
      it 'separates commas' do
        query = described_class.queue_string('first,second')
        expect(query.to_sql).to eq described_class.where(queue_name: %w[first second]).to_sql
      end

      it 'excludes queues commas' do
        query = described_class.queue_string('-first,second')
        expect(query.to_sql).to eq described_class.where.not(queue_name: %w[first second]).or(described_class.where(queue_name: nil)).to_sql
      end

      it 'accepts empty strings' do
        query = described_class.queue_string('')
        expect(query.to_sql).to eq described_class.all.to_sql
      end
    end

    describe '.queue_ordered' do
      it "produces SQL to order by queue order" do
        query_sql = described_class.queue_ordered(%w{one two three}).to_sql
        expect(query_sql).to include(
          "ORDER BY (CASE WHEN queue_name = 'one' THEN 0 WHEN queue_name = 'two' THEN 1 WHEN queue_name = 'three' THEN 2 ELSE 3 END)"
        )
      end
    end

    describe '.priority_ordered' do
      let!(:small_priority_job) { described_class.create!(priority: -50) }
      let!(:large_priority_job) { described_class.create!(priority: 50) }

      it 'orders with smaller number being HIGHER priority' do
        allow(Rails.application.config).to receive(:good_job).and_return({ smaller_number_is_higher_priority: true })
        expect(described_class.priority_ordered.pluck(:priority)).to eq([-50, 50])
      end
    end

    describe '.next_scheduled_at' do
      let(:active_job) { TestJob.new }

      it 'returns an empty array when nothing is scheduled' do
        expect(described_class.all.next_scheduled_at).to eq []
      end

      it 'returns previously scheduled and unscheduled jobs' do
        described_class.enqueue(TestJob.new, scheduled_at: 1.day.ago)
        Timecop.travel 5.minutes.ago do
          described_class.enqueue(TestJob.new, scheduled_at: nil)
        end

        expect(described_class.all.next_scheduled_at(now_limit: 5)).to contain_exactly(
          within(2.seconds).of(1.day.ago),
          within(2.seconds).of(5.minutes.ago)
        )
      end

      it 'returns future scheduled jobs' do
        2.times do
          described_class.enqueue(TestJob.new, scheduled_at: 1.day.from_now)
        end

        expect(described_class.all.next_scheduled_at(limit: 1)).to contain_exactly(
          within(2.seconds).of(1.day.from_now)
        )
      end

      it 'contains both past and future jobs' do
        2.times { described_class.enqueue(TestJob.new, scheduled_at: 1.day.ago) }
        2.times { described_class.enqueue(TestJob.new, scheduled_at: 1.day.from_now) }

        expect(described_class.all.next_scheduled_at(limit: 1, now_limit: 1)).to contain_exactly(
          within(2.seconds).of(1.day.ago),
          within(2.seconds).of(1.day.from_now)
        )
      end
    end

    describe '.display_all' do
      let(:active_job) { TestJob.new }

      it 'does not return jobs after last scheduled at' do
        described_class.enqueue(active_job, scheduled_at: '2021-05-14 09:33:16 +0200')

        expect(described_class.display_all.count).to eq(1)
      end

      it 'does not return jobs after last scheduled at and job id' do
        described_class.enqueue(active_job, scheduled_at: '2021-05-14 09:33:16 +0200')
        job_id = described_class.last!.id

        expect(
          described_class.display_all(after_at: Time.zone.parse('2021-05-14 09:33:16 +0200'), after_id: job_id).count
        ).to eq(0)
      end
    end

    describe '#executable?' do
      let(:good_job) { described_class.create!(active_job_id: SecureRandom.uuid) }

      it 'is true when locked' do
        good_job.with_advisory_lock do
          expect(good_job.executable?).to be true
        end
      end

      it 'is false when job no longer exists' do
        good_job.with_advisory_lock do
          good_job.destroy!
          expect(good_job.executable?).to be false
        end
      end

      it 'is false when the job has finished' do
        good_job.with_advisory_lock do
          good_job.update! finished_at: Time.current
          expect(good_job.executable?).to be false
        end
      end
    end

    describe '#perform' do
      let(:active_job) { TestJob.new("a string") }
      let!(:good_job) { described_class.enqueue(active_job) }

      describe 'return value' do
        it 'returns the results of the job' do
          result = good_job.perform(lock_id: process_id)

          expect(result.value).to eq "a string"
          expect(result.unhandled_error).to be_nil
        end

        context 'when there is an error' do
          let(:active_job) { TestJob.new("whoops", raise_error: true) }
          let(:batch_id) { SecureRandom.uuid }

          let!(:good_job) do
            execution = nil
            GoodJob::CurrentThread.within do
              GoodJob::Batch.within_thread(batch_id: batch_id) do
                GoodJob::CurrentThread.cron_key = 'test_key'
                execution = described_class.enqueue(active_job)
              end
            end

            execution
          end

          it 'returns the error' do
            result = good_job.perform(lock_id: process_id)

            expect(result.value).to be_nil
            expect(result.unhandled_error).to be_an_instance_of TestJob::ExpectedError
          end

          context 'when there is a retry handler' do
            before do
              ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
              allow(GoodJob).to receive(:preserve_job_records).and_return(true)
              TestJob.retry_on(TestJob::ExpectedError, attempts: 2)
            end

            it 'copies job info, including the cron key to the new record' do
              new_record = described_class.order(created_at: :asc).last
              expect(new_record.active_job_id).to eq good_job.active_job_id
              expect(new_record.cron_key).to eq "test_key"
              expect(new_record.batch_id).to eq batch_id
            end
          end

          context 'when there is an retry handler with exhausted attempts' do
            before do
              TestJob.retry_on(TestJob::ExpectedError, attempts: 1)

              good_job.serialized_params["exception_executions"] = { "[TestJob::ExpectedError]" => 1 }
              good_job.save!
            end

            it 'does not modify the original good_job serialized params' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(true)

              expect do
                good_job.perform(lock_id: process_id)
              end.not_to change { good_job.reload.serialized_params["exception_executions"]["[TestJob::ExpectedError]"] }
            end
          end

          context 'when error monitoring service intercepts exception' do
            before do
              # Similar to Sentry monitor's implementation
              # https://github.com/getsentry/raven-ruby/blob/20b260a6d04e0ca01d5cddbd9728e6fc8ae9a90c/lib/raven/integrations/rails/active_job.rb#L21-L31
              TestJob.around_perform do |_job, block|
                block.call
              rescue StandardError => e
                next if rescue_with_handler(e)

                raise e
              end
            end

            it 'returns the error' do
              result = good_job.perform(lock_id: process_id)

              expect(result.value).to be_nil
              expect(result.unhandled_error).to be_an_instance_of TestJob::ExpectedError
            end

            context 'when retry_on is used' do
              before do
                TestJob.retry_on(StandardError, wait: 0, attempts: Float::INFINITY) { nil }
              end

              it 'returns the error' do
                result = good_job.perform(lock_id: process_id)

                expect(result.value).to be_nil
                expect(result.handled_error).to be_an_instance_of TestJob::ExpectedError
              end
            end

            context 'when discard_on is used' do
              before do
                TestJob.discard_on(StandardError) { nil }
              end

              it 'returns the error' do
                result = good_job.perform(lock_id: process_id)

                expect(result.value).to be_nil
                expect(result.handled_error).to be_an_instance_of TestJob::ExpectedError
              end
            end
          end
        end
      end

      it 'preserves the job by default' do
        good_job.perform(lock_id: process_id)
        expect(good_job.reload).to have_attributes(
          performed_at: within(1.second).of(Time.current),
          finished_at: within(1.second).of(Time.current)
        )
      end

      it 'can destroy the job when preserve_job_records is false' do
        allow(GoodJob).to receive(:preserve_job_records).and_return(false)
        good_job.perform(lock_id: process_id)
        expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
      end

      it 'destroys the job when preserving record only on error' do
        allow(GoodJob).to receive(:preserve_job_records).and_return(:on_unhandled_error)
        good_job.perform(lock_id: process_id)
        expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
      end

      context 'when the job is directly re-enqueued' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(false)
          TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
          TestJob.after_perform do
            enqueue(wait: 1.minute)
          end
        end

        it 'does not destroy the execution records' do
          good_job.perform(lock_id: process_id)
          expect { good_job.reload }.not_to raise_error
        end
      end

      context 'when the job is a cron job and records are not preserved' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(false)
          TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
          good_job.update(cron_key: "test_key", cron_at: Time.current)
        end

        it 'preserves the job record anyway' do
          good_job.perform(lock_id: process_id)
          expect(good_job.reload).to have_attributes(
            performed_at: within(1.second).of(Time.current),
            finished_at: within(1.second).of(Time.current)
          )
        end
      end

      it 'raises an error if the job is attempted to be re-run' do
        good_job.update!(finished_at: Time.current)
        expect { good_job.perform(lock_id: process_id) }.to raise_error described_class::PreviouslyPerformedError
      end

      context 'when ActiveJob rescues an error' do
        let(:active_job) { TestJob.new("a string", raise_error: true) }

        before do
          TestJob.retry_on(StandardError, wait: 0, attempts: Float::INFINITY) { nil }
        end

        it 'returns the results of the job' do
          result = good_job.perform(lock_id: process_id)

          expect(result.value).to be_nil
          expect(result.handled_error).to be_a(TestJob::ExpectedError)
        end

        it 'can preserves the job' do
          allow(GoodJob).to receive(:preserve_job_records).and_return(true)

          good_job.perform(lock_id: process_id)

          expect(good_job.reload).to have_attributes(
            error: "TestJob::ExpectedError: Raised expected error",
            performed_at: nil,
            finished_at: nil
          )
        end
      end

      context 'when ActiveJob raises an error' do
        let(:active_job) { TestJob.new("a string", raise_error: true) }

        it 'returns the results of the job' do
          result = good_job.perform(lock_id: process_id)

          expect(result.value).to be_nil
          expect(result.unhandled_error).to be_a(TestJob::ExpectedError)
        end

        describe 'GoodJob.retry_on_unhandled_error behavior' do
          context 'when true' do
            before do
              allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(true)
            end

            it 'leaves the job record unfinished' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(true)

              good_job.perform(lock_id: process_id)

              expect(good_job.reload).to have_attributes(
                error: "TestJob::ExpectedError: Raised expected error",
                performed_at: nil,
                finished_at: nil
              )
            end

            it 'does not destroy the job record' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(false)

              good_job.perform(lock_id: process_id)
              expect { good_job.reload }.not_to raise_error
            end
          end

          context 'when false' do
            before do
              allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
            end

            it 'destroys the job' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(false)

              good_job.perform(lock_id: process_id)
              expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
            end

            it 'can preserve the job' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(true)

              good_job.perform(lock_id: process_id)

              expect(good_job.reload).to have_attributes(
                error: "TestJob::ExpectedError: Raised expected error",
                performed_at: within(1.second).of(Time.current),
                finished_at: within(1.second).of(Time.current)
              )
            end

            it 'preserves the job when preserving record only on error' do
              allow(GoodJob).to receive(:preserve_job_records).and_return(:on_unhandled_error)
              good_job.perform(lock_id: process_id)

              expect(good_job.reload).to have_attributes(
                error: "TestJob::ExpectedError: Raised expected error",
                performed_at: within(1.second).of(Time.current),
                finished_at: within(1.second).of(Time.current)
              )
            end
          end
        end
      end

      context 'when Discrete' do
        before do
          ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
        end

        it 'updates the Job record and creates a Execution record' do
          good_job.perform(lock_id: process_id)

          expect(good_job.reload).to have_attributes(
            executions_count: 1,
            finished_at: within(1.second).of(Time.current)
          )

          execution = good_job.executions.first
          expect(execution).to be_present
          expect(execution).to have_attributes(
            active_job_id: good_job.active_job_id,
            job_class: good_job.job_class,
            queue_name: good_job.queue_name,
            created_at: within(0.001).of(good_job.performed_at),
            scheduled_at: within(0.001).of(good_job.created_at),
            finished_at: within(1.second).of(Time.current),
            duration: be_a(ActiveSupport::Duration),
            error: nil,
            serialized_params: good_job.serialized_params
          )
        end

        context 'when ActiveJob rescues an error' do
          let(:active_job) { TestJob.new("a string", raise_error: true) }
          let!(:good_job) { described_class.enqueue(active_job) }

          before do
            allow(GoodJob).to receive(:preserve_job_records).and_return(true)
            TestJob.retry_on(StandardError, wait: 1.hour, attempts: 2) { nil }
          end

          it 'updates the existing Execution/Job record instead of creating a new one' do
            expect { good_job.perform(lock_id: process_id) }
              .to not_change(described_class, :count)
              .and change { good_job.reload.serialized_params["executions"] }.by(1)
                                                                             .and not_change { good_job.reload.id }
              .and not_change { described_class.count }

            expect(good_job.reload).to have_attributes(
              error: "TestJob::ExpectedError: Raised expected error",
              created_at: within(1.second).of(Time.current),
              performed_at: nil,
              finished_at: nil,
              scheduled_at: within(10.minutes).of(1.hour.from_now) # interval because of retry jitter
            )
            expect(GoodJob::Execution.count).to eq(1)
            execution = good_job.executions.first
            expect(execution).to have_attributes(
              active_job_id: good_job.active_job_id,
              error: "TestJob::ExpectedError: Raised expected error",
              created_at: within(1.second).of(Time.current),
              scheduled_at: within(1.second).of(Time.current),
              finished_at: within(1.second).of(Time.current),
              duration: be_a(ActiveSupport::Duration)
            )
          end
        end

        context 'when retry_job is invoked directly during execution' do
          before do
            TestJob.after_perform do |job|
              job.retry_job wait: 1.second
            end
          end

          it 'finishes the execution but does not finish the job' do
            good_job.perform(lock_id: process_id)

            expect(good_job.reload).to have_attributes(
              performed_at: nil,
              finished_at: nil,
              scheduled_at: within(0.5).of(1.second.from_now)
            )

            expect(good_job.executions.size).to eq(1)
            expect(good_job.executions.first).to have_attributes(
              performed_at: within(1.second).of(Time.current),
              finished_at: within(1.second).of(Time.current),
              duration: be_a(ActiveSupport::Duration)
            )
          end
        end
      end
    end

    describe '#queue_latency' do
      let(:execution) { described_class.create! }

      it 'is nil for future scheduled execution' do
        execution.scheduled_at = 1.minute.from_now
        expect(execution.queue_latency).to be_nil
      end

      it 'is distance between scheduled_at and now for past scheduled job' do
        execution.scheduled_at = 1.minute.ago
        expect(execution.queue_latency).to be_within(0.1).of(Time.zone.now - execution.scheduled_at)
      end

      it 'is distance between created_at and now for queued job' do
        execution.scheduled_at = nil
        expect(execution.queue_latency).to be_within(0.1).of(Time.zone.now - execution.created_at)
      end

      it 'is distance between created_at and performed_at for started job' do
        execution.scheduled_at = nil
        execution.performed_at = 10.seconds.ago
        expect(execution.queue_latency).to eq(execution.performed_at - execution.created_at)
      end
    end

    describe "#runtime_latency" do
      let(:execution) { described_class.create! }

      it 'is nil for queued job' do
        expect(execution.runtime_latency).to be_nil
      end

      it 'is distance between performed_at and now for started job' do
        execution.performed_at = 10.seconds.ago
        execution.finished_at = nil
        expect(execution.runtime_latency).to be_within(0.1).of(Time.zone.now - execution.performed_at)
      end

      it 'is distance between performed_at and finished_at' do
        execution.performed_at = 5.seconds.ago
        execution.finished_at = 1.second.ago
        expect(execution.runtime_latency).to eq(execution.finished_at - execution.performed_at)
      end
    end

    describe '.schedule_ordered' do
      it 'orders by scheduled or created (oldest first)' do
        query = described_class.schedule_ordered
        expect(query.to_sql).to include('ORDER BY')
      end
    end

    describe '.exclude_paused' do
      let!(:default_job) { described_class.create!(queue_name: "default", job_class: "DefaultJob") }
      let!(:mailers_job) { described_class.create!(queue_name: "mailers", job_class: "ActionMailer::MailDeliveryJob") }
      let!(:reports_job) { described_class.create!(queue_name: "reports", job_class: "ReportsJob") }
      let!(:labeled_job) { described_class.create!(queue_name: "default", job_class: "DefaultJob", labels: %w[important urgent]) }
      let!(:other_labeled_job) { described_class.create!(queue_name: "default", job_class: "DefaultJob", labels: ["low_priority"]) }

      before do
        allow(GoodJob.configuration).to receive(:enable_pauses).and_return(enable_pauses)
      end

      context 'when enable_pauses is false' do
        let(:enable_pauses) { false }

        it 'returns all jobs' do
          expect(described_class.exclude_paused).to contain_exactly(default_job, mailers_job, reports_job, labeled_job, other_labeled_job)
        end
      end

      context 'when enable_pauses is true' do
        let(:enable_pauses) { true }

        it 'returns all jobs when nothing is paused' do
          expect(described_class.exclude_paused.count).to eq 5
          expect(described_class.exclude_paused).to contain_exactly(default_job, mailers_job, reports_job, labeled_job, other_labeled_job)
        end

        it 'excludes jobs with paused queue_names' do
          GoodJob::Setting.pause(queue: "default")
          GoodJob::Setting.pause(queue: "mailers")
          expect(described_class.exclude_paused).to contain_exactly(reports_job)
        end

        it 'excludes jobs with paused job_classes' do
          GoodJob::Setting.pause(job_class: "DefaultJob")
          GoodJob::Setting.pause(job_class: "ActionMailer::MailDeliveryJob")
          expect(described_class.exclude_paused).to contain_exactly(reports_job)
        end

        it 'excludes jobs with paused labels' do
          GoodJob::Setting.pause(label: "important")
          expect(described_class.exclude_paused).to contain_exactly(default_job, mailers_job, reports_job, other_labeled_job)
        end

        it 'excludes jobs with any paused label when job has multiple labels' do
          GoodJob::Setting.pause(label: "urgent")
          expect(described_class.exclude_paused).to contain_exactly(default_job, mailers_job, reports_job, other_labeled_job)
        end

        it 'excludes jobs with both paused queue_names and job_classes' do
          GoodJob::Setting.pause(queue: "default")
          GoodJob::Setting.pause(job_class: "ActionMailer::MailDeliveryJob")
          expect(described_class.exclude_paused).to contain_exactly(reports_job)
        end

        it 'excludes jobs with paused queue_names, job_classes, or labels' do
          GoodJob::Setting.pause(queue: "reports")
          GoodJob::Setting.pause(job_class: "ActionMailer::MailDeliveryJob")
          GoodJob::Setting.pause(label: "important")
          expect(described_class.exclude_paused).to contain_exactly(default_job, other_labeled_job)
        end

        it 'handles jobs with nil labels' do
          GoodJob::Setting.pause(label: "important")
          unlabeled_job = described_class.create!(queue_name: "default", job_class: "DefaultJob", labels: nil)
          expect(described_class.exclude_paused).to include(unlabeled_job)
        end

        it 'handles jobs with empty labels array' do
          GoodJob::Setting.pause(label: "important")
          empty_labeled_job = described_class.create!(queue_name: "default", job_class: "DefaultJob", labels: [])
          expect(described_class.exclude_paused).to include(empty_labeled_job)
        end
      end
    end
  end
end
