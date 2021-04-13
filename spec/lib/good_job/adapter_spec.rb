# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Adapter do
  let(:adapter) { described_class.new(execution_mode: :external) }
  let(:active_job) { instance_double(ActiveJob::Base) }
  let(:good_job) { instance_double(GoodJob::Job, queue_name: 'default', scheduled_at: nil) }

  describe '#initialize' do
    it 'guards against improper execution modes' do
      expect do
        described_class.new(execution_mode: :blarg)
      end.to raise_error ArgumentError
    end

    it 'prints a deprecation warning when instantiated in Rails config' do
      allow(ActiveSupport::Deprecation).to receive(:warn)
      allow_any_instance_of(described_class).to receive(:caller).and_return(
        [
          "/rails/config/environments/development.rb:11:in `new'",
          "/rails/config/environments/development.rb:11:in `block in <top (required)>'",
        ]
      )

      described_class.new
      expect(ActiveSupport::Deprecation).to have_received(:warn)
    end
  end

  describe '#enqueue' do
    it 'calls GoodJob::Job.enqueue with parameters' do
      allow(GoodJob::Job).to receive(:enqueue).and_return(good_job)

      adapter.enqueue(active_job)

      expect(GoodJob::Job).to have_received(:enqueue).with(
        active_job,
        create_with_advisory_lock: false,
        scheduled_at: nil
      )
    end

    context 'when async' do
      it 'trigger an execution thread' do
        allow(GoodJob::Job).to receive(:enqueue).and_return(good_job)

        scheduler = instance_double(GoodJob::Scheduler, shutdown: nil, create_thread: nil)
        allow(GoodJob::Scheduler).to receive(:new).and_return(scheduler)

        adapter = described_class.new(execution_mode: :async, poll_interval: -1)
        adapter.enqueue(active_job)

        expect(scheduler).to have_received(:create_thread)
      end
    end
  end

  describe '#enqueue_at' do
    it 'calls GoodJob::Job.enqueue with parameters' do
      allow(GoodJob::Job).to receive(:enqueue).and_return(good_job)

      scheduled_at = 1.minute.from_now

      adapter.enqueue_at(active_job, scheduled_at.to_i)

      expect(GoodJob::Job).to have_received(:enqueue).with(
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
      let(:adapter) { described_class.new(execution_mode: :async) }

      it 'returns true' do
        expect(adapter.execute_async?).to eq true
      end
    end

    context 'when execution mode async_server' do
      let(:adapter) { described_class.new(execution_mode: :async_server) }

      context 'when Rails::Server is defined' do
        before do
          stub_const("Rails::Server", Class.new)
        end

        it 'returns true' do
          expect(adapter.execute_async?).to eq true
          expect(adapter.execute_externally?).to eq false
        end
      end

      context 'when Rails::Server is not defined' do
        before do
          hide_const("Rails::Server")
        end

        it 'returns false' do
          expect(adapter.execute_async?).to eq false
          expect(adapter.execute_externally?).to eq true
        end
      end
    end
  end
end
