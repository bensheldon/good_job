require 'rails_helper'

RSpec.describe GoodJob::Timer do
  describe '#initialize' do
    it 'succeeds' do
      described_class.new
    end
  end

  describe '#push' do
    let(:timer) { described_class.new(max_queue: 2) }

    it 'adds a future to the queue' do
      run_at = 1.minute.from_now
      timer.push(run_at)

      task = timer.queue.first
      expect(task).to be_a Concurrent::ScheduledTask
      expect(task.scheduled_at).to eq(run_at)
    end

    it 'maintains the appropriate queue size' do
      one_minute = 1.minute.from_now
      two_minutes = 2.minutes.from_now

      timer.push(one_minute)
      timer.push(two_minutes)

      (3..5).to_a.each { |i| timer.push(i.minutes.from_now) }

      expect(timer.queue.map(&:scheduled_at)).to eq [one_minute, two_minutes]
    end
  end

  describe '#recipients' do
    let(:recipient) { -> { RUNS << Time.current } }
    let(:timer) { described_class.new(recipient, max_queue: 2) }

    before do
      stub_const "RUNS", Concurrent::Array.new
    end

    it 'triggers the recipient at the appropriate time' do
      scheduled_at = 0.1.seconds.from_now
      timer.push(scheduled_at)
      sleep_until(max: 5) { RUNS.any? }

      expect(RUNS.size).to eq(1)
      expect(RUNS.first).to be_within(0.01.seconds).of(scheduled_at)
    end

    it 'only triggers scheduled items' do
      one_tenth = 0.1.seconds.from_now
      two_tenths = 0.2.seconds.from_now

      timer.push(one_tenth)
      timer.push(two_tenths)
      (3..5).to_a.each { |i| timer.push((i * 0.1).minutes.from_now) }

      sleep(1)

      expect(RUNS.size).to eq 2
    end
  end
end
