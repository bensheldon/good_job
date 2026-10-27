# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Job do
  let(:process_id) { SecureRandom.uuid }
  let(:failure) { ActiveRecord::ConnectionNotEstablished.new('connection lost while finishing') }
  let(:job) { described_class.enqueue(job_class.new) }
  let(:job_class) do
    stub_const 'CompletionRecoveryJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency

      good_job_concurrency_rule(label: 'completion-recovery', perform_limit: 1, apply_label: true)
      class_attribute :performed_ids, default: []
      class_attribute :granted_ids, default: []

      def perform
        self.class.performed_ids << job_id
        self.class.granted_ids << GoodJob::ConcurrencyClaim.granted.where(job_id: job_id).pick(:job_id)
        'completed'
      end
    end)
  end

  around do |example|
    Rails.application.executor.wrap { example.run }
  end

  before do
    allow(described_class).to receive(:sleep)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    job
  end

  # Kill the session server-side, like a real network drop. Closing
  # `raw_connection` directly marks the adapter dirty and blocks reconnects.
  def terminate_connection!
    pid = described_class.lease_connection.select_value("SELECT pg_backend_pid()")
    rails_promise do
      described_class.connection_pool.with_connection do |conn|
        conn.execute("SELECT pg_terminate_backend(#{pid})")
      end
    end.value!
  end

  failure_points = [:execution, :job, :destroy]
  [:advisory, :skiplocked, :hybrid].each do |strategy|
    context "with #{strategy} locking" do
      let(:lock_strategy) { strategy }

      def perform_job
        described_class.perform_with_lock(lock_id: process_id, lock_strategy: lock_strategy)
      end

      failure_points.each do |failure_point|
        it "recovers an interrupted job after its #{failure_point} write fails" do
          failed = false
          target = failure_point == :execution ? GoodJob::Execution : described_class
          method_name = failure_point == :destroy ? :destroy! : :save!
          allow(GoodJob).to receive(:preserve_job_records).and_return(false) if failure_point == :destroy
          allow_any_instance_of(target).to receive(method_name).and_wrap_original do |method, *args, **kwargs|
            if method.receiver.finished_at.present? && !failed
              failed = true
              raise failure
            end
            method.call(*args, **kwargs)
          end

          expect { perform_job }.to raise_error(failure)

          expect(job_class.performed_ids).to eq [job.id]
          expect(job_class.granted_ids).to eq [job.id]
          expect(job.reload.finished_at).to be_nil
          expect(job.executions.last.finished_at).to be_nil
          unless strategy == :advisory
            expect(job).to have_attributes(locked_by_id: nil, locked_at: nil, lock_type: nil)
            expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
          end

          # Recovery follows the normal interrupted-job path, in the same process.
          expect(perform_job.value).to eq 'completed'
          expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
          if failure_point == :destroy
            expect(described_class.exists?(job.id)).to be false
          else
            expect(job.reload.finished_at).to be_present
            expect(job.executions.order(:created_at).first.error_event).to eq 'interrupted'
          end
        end
      end

      it 'does not discard a batch using uncommitted completion fields' do
        batch = GoodJob::BatchRecord.create!(enqueued_at: Time.current)
        job.update!(batch_id: batch.id)
        allow_any_instance_of(job_class).to receive(:perform).and_raise(StandardError, 'job failed')
        allow_any_instance_of(GoodJob::Execution).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
          raise failure if method.receiver.finished_at.present?

          method.call(*args, **kwargs)
        end

        expect { perform_job }.to raise_error(failure)

        expect(job.reload.finished_at).to be_nil
        expect(batch.reload.discarded_at).to be_nil
      end

      it 'recovers after losing the PostgreSQL connection between completion writes', skip: RUBY_PLATFORM.include?('java') do
        disconnected = false
        allow_any_instance_of(described_class).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
          if method.receiver.finished_at.present? && !disconnected
            disconnected = true
            terminate_connection!
          end
          method.call(*args, **kwargs)
        end

        expect { perform_job }.to raise_error do |error|
          expect(error).to be_a(ActiveRecord::StatementInvalid).or(be_a(PG::ConnectionBad)).or(be_a(ActiveRecord::ConnectionNotEstablished))
        end

        expect(job_class.performed_ids).to eq [job.id]
        expect(job.reload.finished_at).to be_nil
        expect(job.executions.last.finished_at).to be_nil
        expect(perform_job.value).to eq 'completed'
        expect(job.reload.finished_at).to be_present
      end
    end
  end

  it 'does not replay completion over a new owner after losing the advisory lock', skip: RUBY_PLATFORM.include?('java') do
    next_process_id = SecureRandom.uuid
    failed = false
    allow_any_instance_of(described_class).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      if method.receiver.finished_at.present? && !failed
        failed = true
        terminate_connection!
        rails_promise do
          described_class.find(job.id).update!(locked_by_id: next_process_id, locked_at: Time.current)
        end.value!
        raise failure
      end
      method.call(*args, **kwargs)
    end

    expect do
      described_class.perform_with_lock(lock_id: process_id, lock_strategy: :advisory)
    end.to raise_error do |error|
      expect(error).to be_a(ActiveRecord::ConnectionNotEstablished).or be_a(PG::ConnectionBad)
    end

    expect(job.reload).to have_attributes(locked_by_id: next_process_id, finished_at: nil)
    expect(job_class.performed_ids).to eq [job.id]
  end

  it 'keeps the worker registered while claim cleanup is waiting for the database' do
    allow(GoodJob.configuration).to receive(:lock_strategy).and_return(:skiplocked)
    allow_any_instance_of(GoodJob::Execution).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      raise failure if method.receiver.finished_at.present?

      method.call(*args, **kwargs)
    end
    failed = false
    allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |method, attributes|
      if attributes == { locked_by_id: nil, locked_at: nil, lock_type: nil } && !failed
        failed = true
        raise failure
      end
      method.call(attributes)
    end
    allow(described_class).to receive(:sleep) do
      expect(GoodJob::JobPerformer.performing_active_job_ids).to include(job.id)
      expect(GoodJob.capsule.tracker.locks).to be_positive
      expect(GoodJob.capsule.tracker.record).to be_persisted
    end

    expect { GoodJob::JobPerformer.new('*').next }.to raise_error(failure)

    expect(described_class).to have_received(:sleep).with(5).once
    expect(GoodJob::JobPerformer.performing_active_job_ids).not_to include(job.id)
    expect(job.reload.locked_by_id).to be_nil
  end
end
