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
      end.to have_enqueued_job(TestJob).with(42, { 'name' => 'Alice' }).on_queue('test_queue')
    end
  end
end
