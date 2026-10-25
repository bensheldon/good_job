# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Job do
  let(:process_id) { SecureRandom.uuid }
  let(:job) { described_class.enqueue(job_class.new) }
  let(:job_class) do
    stub_const 'CompletionRecoveryJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency

      good_job_concurrency_rule(label: 'completion-recovery', perform_limit: 1)
      class_attribute :performed_ids, default: []

      def perform
        self.class.performed_ids << job_id
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

  failure_points = [:execution, :job, :destroy]
  [:advisory, :skiplocked, :hybrid].each do |strategy|
    context "with #{strategy} locking" do
      let(:lock_strategy) { strategy }

      def perform_job
        described_class.perform_with_lock(lock_id: process_id, lock_strategy: lock_strategy)
      end

      failure_points.each do |failure_point|
        it "retries a disconnected #{failure_point} write without performing the job again" do
          attempts = 0
          target = failure_point == :execution ? GoodJob::Execution : described_class
          method_name = failure_point == :destroy ? :destroy! : :save!
          allow(GoodJob).to receive(:preserve_job_records).and_return(false) if failure_point == :destroy
          allow_any_instance_of(target).to receive(method_name).and_wrap_original do |method, *args, **kwargs|
            if method.receiver.finished_at.present?
              attempts += 1
              raise ActiveRecord::ConnectionNotEstablished, 'connection lost while finishing' if attempts == 1
            end
            method.call(*args, **kwargs)
          end

          result = perform_job

          expect(result.value).to eq 'completed'
          expect(attempts).to eq 2
          expect(job_class.performed_ids).to eq [job.id]
          expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
          if failure_point == :destroy
            expect(described_class.exists?(job.id)).to be false
          else
            expect(job.reload).to have_attributes(finished_at: be_present, locked_by_id: nil, locked_at: nil, lock_type: nil)
            expect(job.executions.last.finished_at).to be_present
          end
        end
      end
    end
  end

  [:skiplocked, :hybrid].each do |strategy|
    context "when completion keeps failing with #{strategy} locking" do
      let(:failure) { ActiveRecord::ConnectionNotEstablished.new('connection lost while finishing') }

      before do
        attempts = 0
        allow_any_instance_of(GoodJob::Execution).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
          if method.receiver.finished_at.present?
            attempts += 1
            raise failure if attempts <= 3
          end
          method.call(*args, **kwargs)
        end
      end

      it 'releases the persisted lock and concurrency claim while the process stays alive' do
        expect do
          described_class.perform_with_lock(lock_id: process_id, lock_strategy: strategy)
        end.to raise_error(failure)

        expect(described_class).to have_received(:sleep).with(5).twice
        expect(job.reload).to have_attributes(finished_at: nil, locked_by_id: nil, locked_at: nil, lock_type: nil)
        expect(job.executions.last.finished_at).to be_nil
        expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty

        # The same process can recover the interrupted job without being restarted.
        result = described_class.perform_with_lock(lock_id: process_id, lock_strategy: strategy)
        expect(result.value).to eq 'completed'
        expect(job.reload.finished_at).to be_present
      end

      it 'keeps retrying cleanup if the connection remains unavailable after completion retries' do
        cleanup_attempts = 0
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |method, attributes|
          if method.receiver.klass == described_class && attributes == { locked_by_id: nil, locked_at: nil, lock_type: nil }
            cleanup_attempts += 1
            raise failure if cleanup_attempts <= 4
          end
          method.call(attributes)
        end

        expect do
          described_class.perform_with_lock(lock_id: process_id, lock_strategy: strategy)
        end.to raise_error(failure)

        expect(cleanup_attempts).to eq 5
        expect(job.reload).to have_attributes(finished_at: nil, locked_by_id: nil, locked_at: nil, lock_type: nil)
        expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
        expect(job_class.performed_ids).to eq [job.id]
      end

      it 'does not discard a batch using completion fields that were never committed' do
        batch = GoodJob::BatchRecord.create!(enqueued_at: Time.current)
        job.update!(batch_id: batch.id)
        allow_any_instance_of(job_class).to receive(:perform).and_raise(StandardError, 'job failed')

        expect do
          described_class.perform_with_lock(lock_id: process_id, lock_strategy: strategy)
        end.to raise_error(failure)

        expect(job.reload.finished_at).to be_nil
        expect(batch.reload.discarded_at).to be_nil
      end
    end
  end

  it 'recovers a real lost connection after saving the execution inside the completion transaction', skip: RUBY_PLATFORM.include?('java') do
    disconnected = false
    allow_any_instance_of(described_class).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      if method.receiver.finished_at.present? && !disconnected
        disconnected = true
        described_class.lease_connection.raw_connection.close
      end
      method.call(*args, **kwargs)
    end

    result = described_class.perform_with_lock(lock_id: process_id, lock_strategy: :skiplocked)

    expect(disconnected).to be true
    expect(result.value).to eq 'completed'
    expect(job_class.performed_ids).to eq [job.id]
    expect(job.reload).to have_attributes(finished_at: be_present, locked_by_id: nil, locked_at: nil, lock_type: nil)
    expect(job.executions.last.finished_at).to be_present
    expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
  end

  it 'does not retry unrelated persistence errors' do
    failure = ActiveRecord::StatementInvalid.new('invalid completion statement')
    allow_any_instance_of(GoodJob::Execution).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      raise failure if method.receiver.finished_at.present?

      method.call(*args, **kwargs)
    end

    expect do
      described_class.perform_with_lock(lock_id: process_id, lock_strategy: :skiplocked)
    end.to raise_error(failure)

    expect(described_class).not_to have_received(:sleep)
    expect(job.reload.locked_by_id).to be_nil
    expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
  end

  it 'retries wrapped PostgreSQL connection failures on older Rails versions', skip: RUBY_PLATFORM.include?('java') do
    failed = false
    allow_any_instance_of(GoodJob::Execution).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      if method.receiver.finished_at.present? && !failed
        failed = true
        begin
          raise PG::ConnectionBad, 'connection lost'
        rescue PG::ConnectionBad
          raise ActiveRecord::StatementInvalid, 'could not save completion'
        end
      end
      method.call(*args, **kwargs)
    end

    result = described_class.perform_with_lock(lock_id: process_id, lock_strategy: :skiplocked)

    expect(result.value).to eq 'completed'
    expect(job_class.performed_ids).to eq [job.id]
    expect(job.reload.finished_at).to be_present
  end
end
