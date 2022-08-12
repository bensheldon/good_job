# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::CronEntry do
  subject(:entry) { described_class.new(params) }

  let(:params) do
    {
      key: 'test',
      cron: "* * * * *",
      class: "TestJob",
      args: [42],
      kwargs: { name: "Alice" },
      set: { queue: 'test_queue' },
      description: "Something helpful",
    }
  end

  before do
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform(meaning, name:)
        # nothing
      end
    end)
  end

  describe '#initialize' do
    it 'raises an argument error if cron does not parse to a Fugit::Cron instance' do
      expect { described_class.new(cron: '2017-12-12') }.to raise_error(ArgumentError)
    end
  end

  describe '#all' do
    it 'returns all entries' do
      expect(described_class.all).to be_a(Array)
    end
  end

  describe '#find' do
    it 'returns the entry with the given key' do
      expect(described_class.find('example')).to be_a(described_class)
    end

    it 'raises ActiveRecord:RecordNotFound if the key does not exist' do
      expect { described_class.find('nothing') }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#key' do
    it 'returns the cron key' do
      expect(entry.key).to eq('test')
    end
  end

  describe '#next_at' do
    it 'returns a timestamp of the next time to run' do
      expect(entry.next_at).to eq(Time.current.at_beginning_of_minute + 1.minute)
    end
  end

  describe 'schedule' do
    it 'returns the cron expression' do
      expect(entry.schedule).to eq('* * * * *')
    end

    it 'returns the cron expression for a schedule parsed using natual language' do
      entry = described_class.new(cron: 'every weekday at five')
      expect(entry.schedule).to eq('0 5 * * 1-5')
    end
  end

  describe '#fugit' do
    it 'parses the cron configuration using fugit' do
      allow(Fugit).to receive(:parse).and_call_original

      entry.fugit

      expect(Fugit).to have_received(:parse).with('* * * * *')
    end

    it 'returns an instance of Fugit::Cron' do
      expect(entry.fugit).to be_instance_of(Fugit::Cron)
    end
  end

  describe '#enqueue' do
    include ActiveJob::TestHelper

    before do
      ActiveJob::Base.queue_adapter = :test
    end

    it 'enqueues a job with the correct parameters' do
      expect do
        entry.enqueue
      end.to have_enqueued_job(TestJob).with(42, name: 'Alice').on_queue('test_queue')
    end

    it 'enqueues a job with I18n default locale' do
      I18n.default_locale = :nl

      I18n.with_locale(:en) { entry.enqueue }

      expect(enqueued_jobs.last["locale"]).to eq("nl")
    ensure
      I18n.default_locale = :en
    end

    describe 'job execution' do
      it 'executes the job properly' do
        perform_enqueued_jobs do
          entry.enqueue
        end
      end
    end

    it 'assigns cron_key and cron_at to the execution' do
      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

      cron_at = 10.minutes.ago
      entry.enqueue(cron_at)

      execution = GoodJob::Execution.last
      expect(execution.cron_key).to eq 'test'
      expect(execution.cron_at).to be_within(0.001.seconds).of(cron_at)
    end
  end

  describe '#display_properties' do
    let(:params) do
      {
        key: 'test',
        cron: "* * * * *",
        class: "TestJob",
        args: [42, { name: "Alice" }],
        set: -> { { queue: 'test_queue' } },
        description: "Something helpful",
      }
    end

    it 'returns a hash of properties' do
      expect(entry.display_properties).to eq({
                                               key: 'test',
                                               cron: "* * * * *",
                                               class: "TestJob",
                                               args: [42, { name: "Alice" }],
                                               set: "Lambda/Callable",
                                               description: "Something helpful",
                                             })
    end
  end
end
