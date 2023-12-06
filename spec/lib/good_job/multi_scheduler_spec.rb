# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::MultiScheduler do
  describe '.from_configuration' do
    describe 'multi-scheduling' do
      it 'instantiates multiple schedulers' do
        configuration = GoodJob::Configuration.new({ queues: '*:1;mice,ferrets:2;elephant:4' })
        multi_scheduler = described_class.from_configuration(configuration)

        all_scheduler, rodents_scheduler, elephants_scheduler = multi_scheduler.schedulers

        expect(all_scheduler.stats).to include(
          queues: '*',
          max_threads: 1
        )

        expect(rodents_scheduler.stats).to include(
          queues: 'mice,ferrets',
          max_threads: 2
        )

        expect(elephants_scheduler.stats).to include(
          queues: 'elephant',
          max_threads: 4
        )
      end
    end
  end

  describe '#create_thread' do
    let(:multi_scheduler) { described_class.new([scheduler_1, scheduler_2]) }
    let(:scheduler_1) { instance_double(GoodJob::Scheduler, create_thread: nil) }
    let(:scheduler_2) { instance_double(GoodJob::Scheduler, create_thread: nil) }

    context 'when state is nil' do
      let(:state) { nil }

      it 'always delegates to all schedulers regardless of return value' do
        allow(scheduler_1).to receive(:create_thread).and_return(true)
        allow(scheduler_2).to receive(:create_thread).and_return(false)

        result = multi_scheduler.create_thread(state)
        expect(result).to be true

        expect(scheduler_1).to have_received(:create_thread)
        expect(scheduler_2).to have_received(:create_thread)
      end
    end

    context 'when state has a value' do
      let(:state) { { key: 'value' } }

      it 'delegates to all schedulers if they return nil' do
        result = multi_scheduler.create_thread(state)
        expect(result).to be_nil

        expect(scheduler_1).to have_received(:create_thread).with(state)
        expect(scheduler_2).to have_received(:create_thread).with(state)
      end

      it 'delegates to all schedulers if they return false' do
        allow(scheduler_1).to receive(:create_thread).and_return(false)
        allow(scheduler_2).to receive(:create_thread).and_return(false)

        result = multi_scheduler.create_thread(state)
        expect(result).to be false

        expect(scheduler_1).to have_received(:create_thread)
        expect(scheduler_2).to have_received(:create_thread)
      end

      it 'delegates to each schedulers until one of them returns true' do
        allow(scheduler_1).to receive(:create_thread).and_return(true)
        allow(scheduler_2).to receive(:create_thread).and_return(false)

        result = multi_scheduler.create_thread(state)
        expect(result).to be true

        expect(scheduler_1).to have_received(:create_thread)
        expect(scheduler_2).not_to have_received(:create_thread)
      end
    end
  end

  describe '#stats' do
    let(:configuration) { GoodJob::Configuration.new({ queues: '*:1;mice,ferrets:2;elephant:4' }) }
    let(:multi_scheduler) { described_class.from_configuration(configuration) }

    it 'contains schedulers:' do
      stats = multi_scheduler.stats
      expect(stats[:schedulers].size).to eq 3
      expect(stats[:schedulers].first[:queues]).to eq '*'
    end
  end
end
