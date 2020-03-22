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

  describe 'lockable' do
    describe '.first_advisory_locked_row' do
      it 'returns first row of the query with a lock' do
        expect(job).not_to be_advisory_locked
        result_job = described_class.first_advisory_locked_row(described_class.all)
        expect(result_job).to eq job
        expect(job).to be_advisory_locked
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
