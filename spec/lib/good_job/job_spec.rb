# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Job do
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

  describe '.enqueue' do
    let(:active_job) { TestJob.new }

    it 'creates a new GoodJob record' do
      good_job = nil

      expect do
        good_job = described_class.enqueue(active_job)
      end.to change(described_class, :count).by(1)

      expect(good_job).to have_attributes(
        active_job_id: a_kind_of(String),
        serialized_params: a_kind_of(Hash),
        queue_name: 'test',
        priority: 50,
        scheduled_at: nil
      )
    end

    it 'is schedulable' do
      good_job = described_class.enqueue(active_job, scheduled_at: 1.day.from_now)
      expect(good_job).to have_attributes(
        scheduled_at: within(1.second).of(1.day.from_now)
      )
    end

    it 'can be created with an advisory lock' do
      unlocked_good_job = described_class.enqueue(active_job)
      expect(unlocked_good_job.advisory_locked?).to eq false

      locked_good_job = described_class.enqueue(active_job, create_with_advisory_lock: true)
      expect(locked_good_job.advisory_locked?).to eq true

      locked_good_job.advisory_unlock
    end
  end

  describe '.perform_with_advisory_lock' do
    let(:active_job) { TestJob.new('a string') }
    let!(:good_job) { described_class.enqueue(active_job) }

    it 'performs one job' do
      good_job_2 = described_class.create!(serialized_params: {})

      described_class.all.perform_with_advisory_lock

      expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { good_job_2.reload }.not_to raise_error
    end

    it 'returns the result or nil if not' do
      result = described_class.all.perform_with_advisory_lock

      expect(result).to be_a GoodJob::ExecutionResult
      expect(result.value).to eq 'a string'
      expect(result.unhandled_error).to eq nil

      described_class.enqueue(TestJob.new(true, raise_error: true))
      errored_result = described_class.all.perform_with_advisory_lock

      expect(result).to be_a GoodJob::ExecutionResult
      expect(errored_result.value).to eq nil
      expect(errored_result.unhandled_error).to be_an TestJob::ExpectedError
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

  describe '.next_scheduled_at' do
    let(:active_job) { TestJob.new }

    it 'returns an empty array when nothing is scheduled' do
      expect(described_class.all.next_scheduled_at).to eq []
    end

    it 'returns previously scheduled and unscheduled jobs' do
      described_class.enqueue(active_job, scheduled_at: 1.day.ago)
      travel_to 5.minutes.ago do
        described_class.enqueue(active_job, scheduled_at: nil)
      end

      expect(described_class.all.next_scheduled_at(now_limit: 5)).to contain_exactly(
        within(2.seconds).of(1.day.ago),
        within(2.seconds).of(5.minutes.ago)
      )
    end

    it 'returns future scheduled jobs' do
      2.times do
        described_class.enqueue(active_job, scheduled_at: 1.day.from_now)
      end

      expect(described_class.all.next_scheduled_at(limit: 1)).to contain_exactly(
        within(2.seconds).of(1.day.from_now)
      )
    end

    it 'contains both past and future jobs' do
      2.times { described_class.enqueue(active_job, scheduled_at: 1.day.ago) }
      2.times { described_class.enqueue(active_job, scheduled_at: 1.day.from_now) }

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

      expect(described_class.display_all(after_scheduled_at: Time.zone.parse('2021-05-14 09:33:16 +0200')).count).to eq(0)
    end

    it 'does not return jobs after last scheduled at and job id' do
      described_class.enqueue(active_job, scheduled_at: '2021-05-14 09:33:16 +0200')
      job_id = described_class.last!.id

      expect(
        described_class.display_all(after_scheduled_at: Time.zone.parse('2021-05-14 09:33:16 +0200'), after_id: job_id).count
      ).to eq(0)
    end
  end

  describe '#executable?' do
    let(:good_job) { described_class.create!(active_job_id: SecureRandom.uuid) }

    it 'is true when locked' do
      good_job.with_advisory_lock do
        expect(good_job.executable?).to eq true
      end
    end

    it 'is false when job no longer exists' do
      good_job.with_advisory_lock do
        good_job.destroy!
        expect(good_job.executable?).to eq false
      end
    end

    it 'is false when the job has finished' do
      good_job.with_advisory_lock do
        good_job.update! finished_at: Time.current
        expect(good_job.executable?).to eq false
      end
    end
  end

  describe '#perform' do
    let(:active_job) { TestJob.new("a string") }
    let!(:good_job) { described_class.enqueue(active_job) }

    describe 'return value' do
      it 'returns the results of the job' do
        result = good_job.perform

        expect(result.value).to eq "a string"
        expect(result.unhandled_error).to be_nil
      end

      context 'when there is an error' do
        let(:active_job) { TestJob.new("whoops", raise_error: true) }
        let!(:good_job) do
          GoodJob::CurrentExecution.cron_key = "test_key"
          good_job = described_class.enqueue(active_job)
          GoodJob::CurrentExecution.cron_key = nil
          good_job
        end

        it 'returns the error' do
          result = good_job.perform

          expect(result.value).to eq nil
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
          end

          it 'records the new job UUID on the executing record' do
            good_job.perform
            expect(good_job.reload.retried_good_job_id).to be_present
          end
        end

        context 'when there is an retry handler with exhausted attempts' do
          before do
            TestJob.retry_on(TestJob::ExpectedError, attempts: 1)

            good_job.serialized_params["exception_executions"] = { "[TestJob::ExpectedError]" => 1 }
            good_job.save!
          end

          it 'does not modify the original good_job serialized params' do
            expect do
              good_job.perform
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
            ensure
              nil
            end
          end

          it 'returns the error' do
            result = good_job.perform

            expect(result.value).to eq nil
            expect(result.unhandled_error).to be_an_instance_of TestJob::ExpectedError
          end

          if Gem::Version.new(Rails.version) > Gem::Version.new("6")
            # Necessary instrumentation was added in Rails 6.0
            context 'when retry_on is used' do
              before do
                TestJob.retry_on(StandardError, wait: 0, attempts: Float::INFINITY) { nil }
              end

              it 'returns the error' do
                result = good_job.perform

                expect(result.value).to eq nil
                expect(result.handled_error).to be_an_instance_of TestJob::ExpectedError
              end
            end

            context 'when discard_on is used' do
              before do
                TestJob.discard_on(StandardError) { nil }
              end

              it 'returns the error' do
                result = good_job.perform

                expect(result.value).to eq nil
                expect(result.handled_error).to be_an_instance_of TestJob::ExpectedError
              end
            end
          end
        end
      end
    end

    it 'destroys the job' do
      good_job.perform
      expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'destroys the job when preserving record only on error' do
      allow(GoodJob).to receive(:preserve_job_records).and_return(:on_unhandled_error)
      good_job.perform
      expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'can preserve the job' do
      allow(GoodJob).to receive(:preserve_job_records).and_return(true)

      good_job.perform
      expect(good_job.reload).to have_attributes(
        performed_at: within(1.second).of(Time.current),
        finished_at: within(1.second).of(Time.current)
      )
    end

    it 'raises an error if the job is attempted to be re-run' do
      good_job.update!(finished_at: Time.current)
      expect { good_job.perform }.to raise_error described_class::PreviouslyPerformedError
    end

    context 'when ActiveJob rescues an error' do
      let(:active_job) { TestJob.new("a string", raise_error: true) }

      before do
        TestJob.retry_on(StandardError, wait: 0, attempts: Float::INFINITY) { nil }
      end

      it 'returns the results of the job' do
        result = good_job.perform

        expect(result.value).to be_nil
        expect(result.handled_error).to be_a(TestJob::ExpectedError)
      end

      it 'destroys the job' do
        good_job.perform

        expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
      end

      it 'can preserve the job' do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)

        good_job.perform

        expect(good_job.reload).to have_attributes(
          error: "TestJob::ExpectedError: Raised expected error",
          performed_at: within(1.second).of(Time.current),
          finished_at: within(1.second).of(Time.current)
        )
      end
    end

    context 'when ActiveJob raises an error' do
      let(:active_job) { TestJob.new("a string", raise_error: true) }

      it 'returns the results of the job' do
        result = good_job.perform

        expect(result.value).to eq nil
        expect(result.unhandled_error).to be_a(TestJob::ExpectedError)
      end

      describe 'GoodJob.reperform_jobs_on_standard_error behavior' do
        context 'when true' do
          before do
            allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(true)
          end

          it 'leaves the job record unfinished' do
            allow(GoodJob).to receive(:preserve_job_records).and_return(true)

            good_job.perform

            expect(good_job.reload).to have_attributes(
              error: "TestJob::ExpectedError: Raised expected error",
              performed_at: within(1.second).of(Time.current),
              finished_at: nil
            )
          end

          it 'does not destroy the job record' do
            allow(GoodJob).to receive(:preserve_job_records).and_return(false)

            good_job.perform
            expect { good_job.reload }.not_to raise_error
          end
        end

        context 'when false' do
          before do
            allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
          end

          it 'destroys the job' do
            allow(GoodJob).to receive(:preserve_job_records).and_return(false)

            good_job.perform
            expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
          end

          it 'can preserve the job' do
            allow(GoodJob).to receive(:preserve_job_records).and_return(true)

            good_job.perform

            expect(good_job.reload).to have_attributes(
              error: "TestJob::ExpectedError: Raised expected error",
              performed_at: within(1.second).of(Time.current),
              finished_at: within(1.second).of(Time.current)
            )
          end

          it 'preserves the job when preserving record only on error' do
            allow(GoodJob).to receive(:preserve_job_records).and_return(:on_unhandled_error)
            good_job.perform

            expect(good_job.reload).to have_attributes(
              error: "TestJob::ExpectedError: Raised expected error",
              performed_at: within(1.second).of(Time.current),
              finished_at: within(1.second).of(Time.current)
            )
          end
        end
      end
    end
  end
end
