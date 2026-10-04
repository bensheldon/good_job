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
        expect(GoodJob::Job.count).to be > 3
      end
      cron_manager.shutdown

      job = GoodJob::Job.first
      expect(job).to have_attributes(
        cron_key: 'example',
        priority: -10
      )
    end

    it 'only inserts unique jobs when multiple CronManagers are running' do
      cron_manager = described_class.new(cron_entries, start_on_initialize: true)
      other_cron_manager = described_class.new(cron_entries, start_on_initialize: true)

      wait_until(max: 5) do
        expect(GoodJob::Job.count).to be > 3
      end

      cron_manager.shutdown
      other_cron_manager.shutdown

      jobs = GoodJob::Job.all.to_a
      expect(jobs.size).to eq jobs.map(&:cron_at).uniq.size
    end

    it 'respects the disabled setting' do
      GoodJob::Setting.cron_key_disable('example')

      cron_manager = described_class.new(cron_entries, start_on_initialize: true)
      sleep 2
      cron_manager.shutdown

      expect(GoodJob::Job.count).to eq 0
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

  describe 'graceful restarts' do
    include ActiveSupport::Testing::TimeHelpers

    let(:cron_entries) do
      [
        GoodJob::CronEntry.new(
          key: 'example',
          cron: "0 * * * * *",
          class: "TestJob"
        ),
      ]
    end

    before do
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        def perform
        end
      end)

      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    end

    it "reenqueues jobs scheduled for the previous period" do
      cron_manager = described_class.new(cron_entries, start_on_initialize: false, graceful_restart_period: 5.minutes)
      # Start in the middle of a minute so the live scheduler doesn't also enqueue the next run
      travel_to(Time.current.at_beginning_of_minute + 30.seconds) do
        cron_manager.start

        wait_until(max: 5) do
          expect(GoodJob::Job.count).to eq 5
        end
        cron_manager.shutdown
      end
    end

    it "only attempts times after the last job" do
      cron_entry = cron_entries.first
      current_minute = Time.current.at_beginning_of_minute
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.cron_key = 'example'
        current_thread.cron_at = current_minute - 2.minutes
        TestJob.perform_later
      end
      allow(cron_entry).to receive(:enqueue).and_call_original

      cron_manager = described_class.new(cron_entries, start_on_initialize: true, graceful_restart_period: 5.minutes)

      wait_until(max: 5) do
        expect(GoodJob::Job.pluck(:cron_at)).to include(current_minute - 1.minute, current_minute)
      end
      cron_manager.shutdown
      expect(cron_entry).not_to have_received(:enqueue).with(current_minute - 2.minutes)
      expect(cron_entry).not_to have_received(:enqueue).with(current_minute - 3.minutes)
    end

    it "ignores jobs enqueued after starting when finding the last job" do
      current_minute = Time.current.at_beginning_of_minute
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.cron_key = 'example'
        current_thread.cron_at = current_minute + 1.minute
        TestJob.perform_later
      end

      cron_manager = described_class.new(cron_entries, start_on_initialize: true, graceful_restart_period: 5.minutes)

      wait_until(max: 5) do
        expect(GoodJob::Job.where(cron_at: ...(current_minute + 1.minute)).count).to eq 5
      end
      cron_manager.shutdown
    end

    it "does not reenqueue jobs when job records are not preserved" do
      GoodJob.preserve_job_records = false
      allow(GoodJob.logger).to receive(:warn)

      cron_manager = described_class.new(cron_entries, start_on_initialize: false, graceful_restart_period: 5.minutes)
      cron_manager.start
      cron_manager.shutdown

      expect(GoodJob.logger).to have_received(:warn).with(/ignoring cron_graceful_restart_period/)
      sleep 0.5
      expect(GoodJob::Job.count).to eq 0
    end

    it "does not reenqueue jobs once shut down" do
      cron_manager = described_class.new(cron_entries, start_on_initialize: false, graceful_restart_period: 5.minutes, executor: Concurrent::ImmediateExecutor.new)
      cron_manager.create_graceful_tasks(cron_entries.first)

      expect(GoodJob::Job.count).to eq 0
    end

    it "does not need to reenqueue missed times of a proc that returns a time" do
      entry = GoodJob::CronEntry.new(key: 'example', cron: ->(last_at) { last_at ? last_at + 1.hour : Time.current }, class: "TestJob")
      last_cron_at = 150.minutes.ago.change(usec: 0)
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.cron_key = 'example'
        current_thread.cron_at = last_cron_at
        TestJob.perform_later
      end

      cron_manager = described_class.new([entry], start_on_initialize: true)

      wait_until(max: 5) do
        expect(GoodJob::Job.order(:cron_at).pluck(:cron_at)).to eq [last_cron_at, last_cron_at + 1.hour, last_cron_at + 2.hours]
      end
      cron_manager.shutdown
    end

    it "reports an entry's error without affecting other entries" do
      failing_entry = GoodJob::CronEntry.new(key: 'failing', cron: "0 * * * * *", class: "TestJob")
      allow(failing_entry).to receive(:within).and_raise(StandardError, "within failed")

      cron_manager = described_class.new([failing_entry, *cron_entries], start_on_initialize: false, graceful_restart_period: 5.minutes)
      cron_manager.start

      wait_until(max: 5) do
        expect(GoodJob::Job.where(cron_key: 'example').count).to eq 5
        expect(THREAD_ERRORS.map { |_name, error, _backtrace| error.message }).to eq ["within failed"]
      end
      expect(cron_manager.instance_variable_get(:@tasks).keys).to contain_exactly('failing', 'example')

      cron_manager.shutdown
      THREAD_ERRORS.clear
    end
  end
end
