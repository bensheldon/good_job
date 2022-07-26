# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Adapter do
  let(:adapter) { described_class.new(execution_mode: :external) }
  let(:active_job) { instance_double(ActiveJob::Base) }
  let(:good_job) { instance_double(GoodJob::Execution, queue_name: 'default', scheduled_at: nil) }

  describe '#initialize' do
    it 'uses the global configuration value' do
      allow(GoodJob.configuration).to receive(:execution_mode).and_return(:external)
      adapter = described_class.new
      expect(adapter.execution_mode).to eq(:external)
    end

    it 'guards against improper execution modes' do
      expect do
        described_class.new(execution_mode: :blarg)
      end.to raise_error ArgumentError
    end
  end

  describe '#enqueue' do
    it 'calls GoodJob::Execution.enqueue with parameters' do
      allow(GoodJob::Execution).to receive(:enqueue).and_return(good_job)

      adapter.enqueue(active_job)

      expect(GoodJob::Execution).to have_received(:enqueue).with(
        active_job,
        create_with_advisory_lock: false,
        scheduled_at: nil
      )
    end

    context 'when inline' do
      let(:adapter) { described_class.new(execution_mode: :inline) }

      before do
        stub_const 'PERFORMED', []
        stub_const 'JobError', Class.new(StandardError)
        stub_const 'TestJob', (Class.new(ActiveJob::Base) do
          def perform(succeed: true)
            PERFORMED << Time.current

            raise JobError unless succeed
          end
        end)
      end

      it 'executes the job immediately' do
        adapter.enqueue(TestJob.new(succeed: true))
        expect(PERFORMED.size).to eq 1
      end

      it "raises unhandled exceptions" do
        expect do
          adapter.enqueue(TestJob.new(succeed: false))
        end.to raise_error(JobError)

        expect(PERFORMED.size).to eq 1
      end

      it 'does not execute future scheduled jobs' do
        adapter.enqueue_at(TestJob.new, 1.minute.from_now.to_f)
        expect(PERFORMED.size).to eq 0
        expect(GoodJob::Job.count).to eq 1
      end
    end

    context 'when async' do
      it 'triggers an execution thread and the notifier' do
        allow(GoodJob::Execution).to receive(:enqueue).and_return(good_job)
        allow(GoodJob::Notifier).to receive(:notify)

        scheduler = instance_double(GoodJob::Scheduler, shutdown: nil, create_thread: nil)
        allow(GoodJob::Scheduler).to receive(:new).and_return(scheduler)

        poller = instance_double(GoodJob::Poller, recipients: [], shutdown: nil)
        allow(GoodJob::Poller).to receive(:new).and_return(poller)

        adapter = described_class.new(execution_mode: :async_all)
        adapter.enqueue(active_job)

        expect(scheduler).to have_received(:create_thread)
        expect(GoodJob::Notifier).to have_received(:notify)
      end
    end
  end

  describe '#enqueue_at' do
    it 'calls GoodJob::Execution.enqueue with parameters' do
      allow(GoodJob::Execution).to receive(:enqueue).and_return(good_job)

      scheduled_at = 1.minute.from_now

      adapter.enqueue_at(active_job, scheduled_at.to_i)

      expect(GoodJob::Execution).to have_received(:enqueue).with(
        active_job,
        create_with_advisory_lock: false,
        scheduled_at: scheduled_at.change(usec: 0)
      )
    end
  end

  describe '#shutdown' do
    it 'is callable' do
      adapter.shutdown
    end
  end

  describe '#execute_async?' do
    context 'when execution mode async_all' do
      let(:adapter) { described_class.new(execution_mode: :async_all) }

      it 'returns true' do
        expect(adapter.execute_async?).to be true
      end
    end

    context 'when execution mode async' do
      let(:adapter) { described_class.new(execution_mode: :async) }

      context 'when Rails::Server is defined' do
        before do
          stub_const("Rails::Server", Class.new)
        end

        it 'returns true' do
          expect(adapter.execute_async?).to be true
          expect(adapter.execute_externally?).to be false
        end
      end

      context 'when Rails::Server is not defined' do
        before do
          hide_const("Rails::Server")
        end

        it 'returns false' do
          expect(adapter.execute_async?).to be false
          expect(adapter.execute_externally?).to be true
        end
      end
    end

    context 'when execution mode async_server' do
      let(:adapter) { described_class.new(execution_mode: :async_server) }

      context 'when Rails::Server is defined' do
        before do
          stub_const("Rails::Server", Class.new)
        end

        it 'returns true' do
          expect(adapter.execute_async?).to be true
          expect(adapter.execute_externally?).to be false
        end
      end

      context 'when Rails::Server is not defined' do
        before do
          hide_const("Rails::Server")
        end

        it 'returns false' do
          expect(adapter.execute_async?).to be false
          expect(adapter.execute_externally?).to be true
        end
      end
    end
  end
end
