# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::CronManager do
  let(:cron_entries) { [] }

  describe '#start' do
    it 'stops the cron manager' do
      cron_manager = described_class.new(cron_entries, start_on_initialize: false)
      expect do
        cron_manager.start
      end.to change(cron_manager, :running?).from(false).to true
    end
  end

  describe '#stop' do
    it 'starts the cron manager' do
      cron_manager = described_class.new(cron_entries, start_on_initialize: true)
      expect do
        cron_manager.shutdown
      end.to change(cron_manager, :running?).from(true).to false
    end
  end

  describe 'schedules' do
    let(:cron_entries) do
      [
        GoodJob::CronEntry.new(
          key: 'example',
          cron: "* * * * * *", # cron-style scheduling format by fugit gem, allows seconds resolution
          class: "TestJob", # reference the Job class with a string
          args: [42, { name: "Alice" }], # arguments to pass.  Could also allow a Proc for dynamic args, but problematic?
          set: { priority: -10 }, # additional ActiveJob properties. Could also allow a Proc for dynamic args, but problematic?
          description: "Something helpful" # optional description that appears in Dashboard
        ),
      ]
    end

    before do
      stub_const 'TestJob', Class.new(ActiveJob::Base)
      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    end

    it 'executes the defined tasks' do
      cron_manager = described_class.new(cron_entries, start_on_initialize: true)

      wait_until(max: 5) do
        expect(GoodJob::Execution.count).to be > 3
      end
      cron_manager.shutdown

      execution = GoodJob::Execution.first
      expect(execution).to have_attributes(
        cron_key: 'example',
        priority: -10
      )
    end

    it 'only inserts unique jobs when multiple CronManagers are running' do
      cron_manager = described_class.new(cron_entries, start_on_initialize: true)
      other_cron_manager = described_class.new(cron_entries, start_on_initialize: true)

      wait_until(max: 5) do
        expect(GoodJob::Execution.count).to be > 3
      end

      cron_manager.shutdown
      other_cron_manager.shutdown

      executions = GoodJob::Execution.all.to_a
      expect(executions.size).to eq executions.map(&:cron_at).uniq.size
    end

    it 'respects the disabled setting' do
      GoodJob::Setting.cron_key_disable('example')

      cron_manager = described_class.new(cron_entries, start_on_initialize: true)
      sleep 2
      cron_manager.shutdown

      expect(GoodJob::Execution.count).to eq 0
    end

    context 'when schedule is a proc' do
      let(:my_proc) { ->(last_at) { last_at ? last_at + 1.second : Time.current } }
      let(:cron_entries) do
        [
          GoodJob::CronEntry.new(
            key: 'example',
            cron: my_proc,
            class: "TestJob"
          ),
        ]
      end

      it 'executes the defined tasks' do
        allow(my_proc).to receive(:call).and_call_original
        cron_manager = described_class.new(cron_entries, start_on_initialize: true)

        wait_until(max: 5) do
          expect(GoodJob::Job.count).to be > 2
        end
        cron_manager.shutdown

        expect(my_proc).to have_received(:call).with(nil).once
        expect(my_proc).to have_received(:call).with(an_instance_of(ActiveSupport::TimeWithZone)).at_least(2).times
      end
    end
  end
end
