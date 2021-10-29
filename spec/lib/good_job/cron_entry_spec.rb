# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::CronEntry do
  subject(:entry) { described_class.new(params) }

  let(:params) do
    {
      key: 'test',
      cron: "* * * * *",
      class: "TestJob",
      args: [42, { name: "Alice" }],
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

  describe '#enqueue' do
    before do
      ActiveJob::Base.queue_adapter = :test
    end

    it 'enqueues a job with the correct parameters' do
      expect do
        entry.enqueue
      end.to have_enqueued_job(TestJob).with(42, { name: 'Alice' }).on_queue('test_queue')
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
