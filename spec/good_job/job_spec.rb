require 'rails_helper'

RSpec.describe GoodJob::Job do
  let(:job) { described_class.create! }

  before do
    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*_args, **_kwargs)
        nil
      end
    end)
  end

  describe '.to_performer' do
    it 'performs a job' do
      allow_any_instance_of(described_class).to receive(:perform), &:destroy!

      job_1 = described_class.create!
      job_2 = described_class.create!

      performer = described_class.to_performer
      5.times { performer.next }

      expect { job_1.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { job_2.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'sets scheduled_at condition dynamically' do
      allow_any_instance_of(described_class).to receive(:perform), &:destroy!
      job = described_class.create!(scheduled_at: 12.hours.from_now)
      performer = described_class.to_performer

      performer.next
      expect { job.reload }.not_to raise_error

      travel 1.day do
        performer.next
        expect { job.reload }.to raise_error ActiveRecord::RecordNotFound
      end
    end
  end

  describe 'lockable' do
    describe '.advisory_lock' do
      around do |example|
        RSpec.configure do |config|
          config.expect_with :rspec do |c|
            original_max_formatted_output_length = c.instance_variable_get(:@max_formatted_output_length)

            c.max_formatted_output_length = 1000000
            example.run

            c.max_formatted_output_length = original_max_formatted_output_length
          end
        end
      end

      it 'generates appropriate SQL' do
        query = described_class.where(priority: 99).order(priority: :desc).limit(2).advisory_lock

        expect(normalize_sql(query.to_sql)).to eq normalize_sql(<<~SQL)
          SELECT "good_jobs".*
          FROM "good_jobs"
          WHERE "good_jobs"."id" IN (
            WITH "rows" AS (
              SELECT "good_jobs"."id"
              FROM "good_jobs"
              WHERE "good_jobs"."priority" = 99
              ORDER BY "good_jobs"."priority" DESC
            )
            SELECT "rows"."id"
            FROM "rows"
            WHERE pg_try_advisory_lock(('x'||substr(md5('good_jobs' || "rows"."id"::text), 1, 16))::bit(64)::bigint)
            LIMIT 2
          )
          ORDER BY "good_jobs"."priority" DESC
        SQL
      end

      it 'returns first row of the query with a lock' do
        expect(job).not_to be_advisory_locked
        result_job = described_class.advisory_lock.first
        expect(result_job).to eq job
        expect(job).to be_advisory_locked
      end
    end

    describe '.with_advisory_lock' do
      it 'opens a block with a lock' do
        records = nil
        described_class.limit(2).with_advisory_lock do |results|
          records = results
          expect(records).to all be_advisory_locked
        end

        expect(records).to all be_advisory_unlocked
      end
    end

    describe '#advisory_lock' do
      it 'results in a locked record' do
        job.advisory_lock!
        expect(job.advisory_locked?).to be true
        expect(job.owns_advisory_lock?).to be true

        other_thread_owns_advisory_lock = Concurrent::Promises.future(job, &:owns_advisory_lock?).value!
        expect(other_thread_owns_advisory_lock).to be false
      end
    end

    describe '#advisory_unlock' do
      it 'unlocks the record' do
        job.advisory_lock!

        expect do
          job.advisory_unlock
        end.to change(job, :advisory_locked?).from(true).to(false)
      end

      it 'unlocks the record only once' do
        job.advisory_lock!
        job.advisory_lock!

        expect do
          job.advisory_unlock
        end.not_to change(job, :advisory_locked?).from(true)
      end
    end

    describe '#advisory_unlock!' do
      it 'unlocks the record entirely' do
        job.advisory_lock!
        job.advisory_lock!

        expect do
          job.advisory_unlock!
        end.to change(job, :advisory_locked?).from(true).to(false)
      end
    end
  end

  describe 'create_with_lock' do
    it 'causes the job to be saved and locked' do
      job = described_class.new
      job.create_with_advisory_lock = true
      job.save!

      expect(job).to be_advisory_locked
    end
  end

  it 'is lockable' do
    ActiveRecord::Base.clear_active_connections!
    job.advisory_lock!

    expect do
      Concurrent::Promises.future(job, &:advisory_lock!).value!
    end.to raise_error GoodJob::Lockable::RecordAlreadyAdvisoryLockedError
  end

  describe '#perform' do
    it 'destroys the job after running' do
      good_job = described_class.create(
        serialized_params: {
          "job_class" => "ExampleJob",
          "job_id" => "cf2aeba7-cd0e-4cc4-a05b-23269bc20dbf",
          "provider_job_id" => nil,
          "queue_name" => "test",
          "priority" => 10,
          "arguments" => [],
          "executions" => 0,
          "exception_executions" => {},
          "locale" => "en",
          "timezone" => "UTC",
          "enqueued_at" => "2020-03-22T19:10:10Z",
        }
      )

      good_job.perform

      expect { good_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end
  end
end
