# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::Capsule do
  describe '#initialize' do
    it 'does not start' do
      capsule = described_class.new
      expect(capsule).not_to be_running
    end
  end

  describe '#start' do
    it 'creates execution objects' do
      capsule = described_class.new
      expect { capsule.start }
        .to change(GoodJob::Notifier.instances, :size).by(1)
        .and change(GoodJob::Scheduler.instances, :size).by(1)
        .and change(GoodJob::Poller.instances, :size).by(1)
        .and change(GoodJob::Poller.instances, :size).by(1)
      capsule.shutdown
    end

    it 'is safe to call from multiple threads' do
      capsule = described_class.new
      Array.new(100) { Thread.new { capsule.start } }.each(&:join)
      capsule.shutdown
      expect(GoodJob::Scheduler.instances.size).to eq 1
    end
  end

  describe '#shutdown' do
    it 'operates if the capsule has not been started' do
      capsule = described_class.new
      expect { capsule.shutdown }.not_to raise_error
    end
  end

  describe '#create_thread' do
    it 'passes the job state to the scheduler' do
      scheduler = instance_double(GoodJob::Scheduler, create_thread: nil, shutdown?: true, shutdown: nil)
      allow(GoodJob::Scheduler).to receive(:new).and_return(scheduler)
      job_state = "STATE"

      capsule = described_class.new
      capsule.start
      capsule.create_thread(job_state)

      expect(scheduler).to have_received(:create_thread).with(job_state)
    end

    it 'starts the capsule if it is not running' do
      capsule = described_class.new
      expect { capsule.create_thread }.to change(capsule, :running?).from(false).to(true)
    end

    it 'will not start the capsule if it has been shutdown' do
      capsule = described_class.new
      capsule.start
      capsule.shutdown
      expect { capsule.create_thread }.not_to change(capsule, :running?).from(false)
    end

    it 'returns nil if the capsule is not running' do
      capsule = described_class.new
      capsule.shutdown
      expect(capsule.create_thread).to be_nil
    end
  end
end
