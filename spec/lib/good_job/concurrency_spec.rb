# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Concurrency do
  describe GoodJob::Concurrency::ThreadPool do
    let(:pool) { described_class.new(max_threads: 2, max_queue: 2, idletime: 0.2) }

    after { pool.kill }

    it 'accepts tasks up to max_threads + max_queue and discards the rest' do
      latch = Concurrent::CountDownLatch.new(1)
      accepted = Array.new(6) { pool.post { latch.wait(5) } }
      expect(accepted).to eq [true, true, true, true, false, false]
      expect(pool.ready_worker_count).to eq 0
      latch.count_down
    end

    it 'reaps idle workers' do
      pool.post { nil }
      wait_until(max: 2) { expect(pool.length).to eq 0 }
    end

    it 'shuts down gracefully, completing in-flight tasks' do
      done = GoodJob::Concurrency::Event.new
      pool.post do
        sleep 0.1
        done.set
      end
      pool.shutdown
      expect(pool.post { nil }).to be false
      expect(pool.wait_for_termination(2)).to be true
      expect(done).to be_set
      expect(pool).to be_shutdown
    end

    it 'can be killed' do
      pool.post { sleep 10 }
      pool.shutdown
      expect(pool.wait_for_termination(0.1)).to be false
      pool.kill
      expect(pool.wait_for_termination(1)).to be true
    end
  end

  describe GoodJob::Concurrency::Future do
    it 'runs on the executor and notifies observers' do
      observed = Queue.new
      future = described_class.new(args: [2], executor: GoodJob::Concurrency.global_executor) { |x| x * 21 }
      future.add_observer { |_time, value, reason| observed << [value, reason] }
      future.execute
      expect(future.value(2)).to eq 42
      expect(observed.pop(timeout: 1)).to eq [42, nil]
    end

    it 'captures errors' do
      future = described_class.new { raise "boom" }.execute.wait(2)
      expect(future).to be_rejected
      expect(future.reason.message).to eq "boom"
    end
  end

  describe GoodJob::Concurrency::ScheduledTask do
    it 'runs after the delay' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      task = described_class.new(0.2) { Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }.execute
      expect(task.value(2)).to be >= 0.2
    end

    it 'can be cancelled before running, notifying observers' do
      timer_set = GoodJob::Concurrency::TimerSet.new
      reasons = []
      task = described_class.new(5, timer_set: timer_set) { nil }
      task.add_observer { |_time, _value, reason| reasons << reason }
      task.execute
      expect(timer_set.length).to eq 1
      expect(task.cancel).to be true
      expect(timer_set.length).to eq 0
      expect(reasons.first).to be_a GoodJob::Concurrency::CancelledOperationError
    ensure
      timer_set&.shutdown
    end
  end

  describe GoodJob::Concurrency::TimerTask do
    it 'runs repeatedly until shutdown' do
      count = Concurrent::AtomicFixnum.new
      task = described_class.new(execution_interval: 0.05, run_now: true) { count.increment }.execute
      wait_until(max: 2) { expect(count.value).to be >= 3 }
      task.shutdown
      expect(task.wait_for_termination(1)).to be true
    end
  end

  describe GoodJob::Concurrency::Event do
    it 'waits until set' do
      event = described_class.new
      expect(event.wait(0.05)).to be false
      Thread.new do
        sleep 0.05
        event.set
      end
      expect(event.wait(1)).to be true
    end
  end
end
