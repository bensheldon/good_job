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

      it "can handle spaces in the configuration" do
        configuration = GoodJob::Configuration.new({ queues: ' +  mice , ferrets: 2 ; elephant : 4 ; ' })
        multi_scheduler = described_class.from_configuration(configuration)

        rodents_scheduler, elephants_scheduler = multi_scheduler.schedulers

        expect(rodents_scheduler.stats).to include(
          queues: '+  mice , ferrets',
          max_threads: 2
        )
        expect(rodents_scheduler.send(:performer).send(:parsed_queues)).to eq({ include: %w[mice ferrets], ordered_queues: true })

        expect(elephants_scheduler.stats).to include(
          queues: 'elephant',
          max_threads: 4
        )
        expect(elephants_scheduler.send(:performer).send(:parsed_queues)).to eq({ include: ["elephant"] })
      end

      it 'converts thread queue counts with to_i, including zero' do
        configuration = GoodJob::Configuration.new({ queues: 'zero:0;text:many;prefix:2jobs' })
        scheduler = instance_double(GoodJob::Scheduler)
        allow(GoodJob::Scheduler).to receive(:new).and_return(scheduler)
        described_class.from_configuration(configuration)
        expect(GoodJob::Scheduler).to have_received(:new).with(anything, hash_including(max_threads: 0)).twice
        expect(GoodJob::Scheduler).to have_received(:new).with(anything, hash_including(max_threads: 2)).once
      end
    end

    describe 'fiber counts', :fiber_isolation, :requires_async do
      it 'uses per-queue overrides as fiber counts' do
        configuration = GoodJob::Configuration.new({ fibers: 25, queues: 'mice:10;elephants' })

        multi_scheduler = described_class.from_configuration(configuration)

        expect(multi_scheduler.schedulers.map(&:stats)).to contain_exactly(
          include(queues: 'mice', max_fibers: 10),
          include(queues: 'elephants', max_fibers: 25)
        )
      end
    end

    describe 'fiber fallback' do
      it 'caps fallback thread pools at max_threads in async mode' do
        configuration = GoodJob::Configuration.new({ execution_mode: :async, fibers: 25, max_threads: 5, queues: 'serial:1;mice:80;elephants' })
        allow(GoodJob::Scheduler).to receive(:validate_fiber_execution!).and_raise(ArgumentError, "fibers unsupported here")
        allow(GoodJob.logger).to receive(:error)

        multi_scheduler = described_class.from_configuration(configuration)

        expect(multi_scheduler.schedulers.map(&:stats)).to contain_exactly(
          include(queues: 'serial', max_threads: 1),
          include(queues: 'mice', max_threads: 5),
          include(queues: 'elephants', max_threads: 5)
        )
        expect(GoodJob.logger).to have_received(:error).with(/ignoring `fibers`/)
      end

      it 'raises for the CLI worker regardless of execution mode' do
        allow(GoodJob).to receive(:cli?).and_return(true)
        configuration = GoodJob::Configuration.new({ execution_mode: :async_all, fibers: 25 })
        allow(GoodJob::Scheduler).to receive(:validate_fiber_execution!).and_raise(ArgumentError, "fibers unsupported here")

        expect { described_class.from_configuration(configuration) }
          .to raise_error(ArgumentError, "fibers unsupported here")
      end

      it 'falls back for an in-process worker regardless of execution mode' do
        allow(GoodJob).to receive(:cli?).and_return(false)
        configuration = GoodJob::Configuration.new({ execution_mode: :external, fibers: 25, max_threads: 5 })
        allow(GoodJob::Scheduler).to receive(:validate_fiber_execution!).and_raise(ArgumentError, "fibers unsupported here")
        allow(GoodJob.logger).to receive(:error)

        multi_scheduler = described_class.from_configuration(configuration)

        expect(multi_scheduler.schedulers.map(&:stats)).to contain_exactly(include(max_threads: 5))
        expect(GoodJob.logger).to have_received(:error).with(/ignoring `fibers`/)
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

    it 'counts active execution threads separately from jobs' do
      thread_scheduler = instance_double(GoodJob::Scheduler, stats: { active_threads: 2 })
      fiber_scheduler = instance_double(GoodJob::Scheduler, stats: { active_threads: 1, active_fibers: 8 })
      expect(described_class.new([thread_scheduler, fiber_scheduler]).stats).to include(
        active_execution_thread_count: 3,
        active_execution_count: 10
      )
    end
  end
end
