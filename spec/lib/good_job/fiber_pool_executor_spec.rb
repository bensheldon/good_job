# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::FiberPoolExecutor, :requires_async do
  let(:executor) { described_class.new(max_fibers: 5, name: "test-executor") }

  after do
    executor.kill unless executor.shutdown?
    executor.wait_for_termination(5)
  end

  describe '#post' do
    it 'executes tasks and passes arguments' do
      results = Concurrent::Array.new
      expect(executor.post(1, 2) { |a, b| results << (a + b) }).to be true
      wait_until { expect(results).to eq [3] }
    end

    it 'executes tasks concurrently as fibers' do
      results = Concurrent::Array.new
      monotonic_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      10.times do |i|
        executor.post(i) do |n|
          sleep(0.2)
          results << n
        end
      end
      wait_until(max: 5) { expect(results.size).to eq 10 }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_start

      # 10 tasks x 0.2s at 5 fibers is ~0.4s when interleaved, 2s when serial
      expect(elapsed).to be < 1.5
    end

    it 'resumes sleeping fibers while waiting for new work' do
      completed = Concurrent::AtomicBoolean.new(false)
      executor.post do
        sleep(0.2)
        completed.make_true
      end

      wait_until { expect(completed.true?).to be true }
    end

    it 'returns false after shutdown' do
      executor.shutdown
      expect(executor.post { nil }).to be false
    end

    it 'isolates GoodJob::CurrentThread state between concurrent fibers', :fiber_isolation do
      results = Concurrent::Hash.new
      2.times do |i|
        executor.post(i) do |n|
          GoodJob::CurrentThread.active_job = "job-#{n}"
          GoodJob::CurrentThread.retry_now = n.zero?
          sleep(0.2)
          results[n] = [GoodJob::CurrentThread.active_job, GoodJob::CurrentThread.retry_now]
        end
      end

      wait_until { expect(results.size).to eq 2 }
      expect(results[0]).to eq ["job-0", true]
      expect(results[1]).to eq ["job-1", false]
    end

    it 'reports task errors without stopping other fibers' do
      errors = Concurrent::Array.new
      allow(GoodJob).to receive(:_on_thread_error) { |error| errors << error }

      results = Concurrent::Array.new
      executor.post { raise "boom" }
      3.times do |i|
        executor.post(i) do |n|
          sleep(0.2)
          results << n
        end
      end

      wait_until { expect(results.size).to eq 3 }
      expect(errors.map(&:message)).to eq ["boom"]
      expect(executor.running?).to be true
      wait_until { expect(executor.ready_worker_count).to eq 5 }
      expect(executor.post { results << :after }).to be true
      wait_until { expect(results).to include :after }
    end

    it 'reports non-StandardError exceptions without stopping other fibers' do
      errors = Concurrent::Array.new
      allow(GoodJob).to receive(:_on_thread_error) { |error| errors << error }

      results = Concurrent::Array.new
      3.times do |i|
        executor.post(i) do |n|
          sleep(0.2)
          results << n
        end
      end
      executor.post { raise Exception, "task failed" } # rubocop:disable Lint/RaiseException

      wait_until { expect(results.size).to eq 3 }
      expect(results).to contain_exactly(0, 1, 2)
      expect(errors.map(&:message)).to eq ["task failed"]
      expect(executor.running?).to be true
      expect(executor.post { results << :after }).to be true
      wait_until { expect(results).to include :after }
    end

    it 'classifies cancellation and process signals as fatal' do
      [Async::Stop.new, SystemExit.new, SignalException.new("TERM")].each do |error|
        expect(described_class.fatal_exception?(error)).to be true
      end
      expect(described_class.fatal_exception?(Exception.new)).to be false
      expect(described_class.fatal_exception?(nil)).to be false
    end

    it 'queues tasks when all fibers are busy' do
      latch = Concurrent::CountDownLatch.new(1)
      completed = Concurrent::AtomicFixnum.new(0)
      accepted = 20.times.count do
        executor.post do
          latch.wait(5)
          completed.increment
        end
      end

      expect(accepted).to eq 20
      expect(executor.ready_worker_count).to eq 0
      latch.count_down
      wait_until { expect(completed.value).to eq 20 }
      wait_until { expect(executor.ready_worker_count).to eq 5 }
    end

    it 'runs deferred callbacks after releasing fiber capacity' do
      available_workers = Concurrent::AtomicFixnum.new(0)

      executor.post do
        expect(executor.defer_after_current_task { available_workers.value = executor.ready_worker_count }).to be true
      end

      wait_until { expect(available_workers.value).to eq 5 }
    end
  end

  describe '#initialize' do
    it 'raises when max_fibers is less than 1' do
      expect { described_class.new(max_fibers: 0) }.to raise_error(ArgumentError, /max_fibers/)
    end
  end

  describe '#ready_worker_count' do
    it 'reflects pending tasks' do
      expect(executor.ready_worker_count).to eq 5

      latch = Concurrent::CountDownLatch.new(1)
      3.times { executor.post { latch.wait(5) } }
      wait_until { expect(executor.ready_worker_count).to eq 2 }

      latch.count_down
      wait_until { expect(executor.ready_worker_count).to eq 5 }
    end
  end

  describe 'reactor crash recovery' do
    it 'restores capacity after the reactor dies with running fibers' do
      started = Concurrent::CountDownLatch.new(5)
      blocker = Concurrent::CountDownLatch.new(1)
      5.times do
        executor.post do
          started.count_down
          blocker.wait(5)
        end
      end
      expect(started.wait(5)).to be true
      expect(executor.ready_worker_count).to eq 0

      reactor = executor.instance_variable_get(:@reactor_thread)
      reactor.kill
      reactor.join

      expect(executor.ready_worker_count).to eq 5

      completed = Concurrent::AtomicBoolean.new(false)
      expect(executor.post { completed.make_true }).to be true
      wait_until { expect(completed.true?).to be true }
    end

    [false, true].each do |shutdown|
      it "runs tasks posted during reactor failure (shutdown=#{shutdown})" do
        failed = Concurrent::Event.new
        release = Concurrent::Event.new
        first = true
        reader = executor.instance_variable_get(:@wakeup_reader)
        allow(reader).to receive(:wait_readable).and_wrap_original do |original|
          if first
            first = false
            raise IOError, 'reactor failure'
          end
          original.call
        end
        allow(GoodJob).to receive(:_on_thread_error) do
          failed.set
          release.wait(5)
        end
        completed = Concurrent::Array.new
        executor.post { completed << 1 }
        expect(failed.wait(5)).to be true
        executor.post { completed << 2 }
        executor.shutdown if shutdown
        release.set
        expect(executor.wait_for_termination(5)).to be true if shutdown
        wait_until { expect(completed).to contain_exactly(1, 2) }
        expect(executor.ready_worker_count).to eq 5
      ensure
        release&.set
      end
    end

    it 'preserves queued work while the reactor is blocked on capacity' do
      started = Concurrent::CountDownLatch.new(5)
      5.times do
        executor.post do
          started.count_down
          sleep 60
        end
      end
      expect(started.wait(5)).to be true
      completed = Concurrent::Array.new
      3.times { |i| executor.post { completed << i } }
      reactor = executor.instance_variable_get(:@reactor_thread)
      reactor.kill
      expect(reactor.join(5)).to eq reactor
      wait_until { expect(completed).to contain_exactly(0, 1, 2) }
      expect(executor.ready_worker_count).to eq 5
    end
  end

  describe '#shutdown' do
    it 'drains accepted work when shutdown precedes reactor startup' do
      entered = Concurrent::Event.new
      release = Concurrent::Event.new
      completed = Concurrent::Array.new
      allow(executor).to receive(:run_reactor).and_wrap_original do |original|
        entered.set
        release.wait(5)
        original.call
      end
      executor.post { completed << :done }
      expect(entered.wait(5)).to be true
      executor.shutdown
      expect(executor.post { completed << :unexpected }).to be false
      release.set
      expect(executor.wait_for_termination(5)).to be true
      expect(completed).to eq [:done]
      expect(executor.instance_variable_get(:@wakeup_reader)).to be_closed
    ensure
      release&.set
    end

    it 'drains in-flight tasks and stops the reactor' do
      wakeup_ios = [
        executor.instance_variable_get(:@wakeup_reader),
        executor.instance_variable_get(:@wakeup_writer),
      ]
      started = Concurrent::CountDownLatch.new(5)
      release = Concurrent::Event.new
      completed = Concurrent::Array.new
      8.times do |i|
        executor.post do
          started.count_down
          release.wait(5)
          completed << i
        end
      end
      expect(started.wait(5)).to be true
      executor.shutdown

      expect(executor.running?).to be false
      expect(executor.wait_for_termination(0.01)).to be false
      release.set
      expect(executor.wait_for_termination(5)).to be true
      expect(executor.shutdown?).to be true
      expect(completed).to match_array((0...8).to_a)
      expect(wakeup_ios).to all(be_closed)
      executor.shutdown
      expect(executor.wait_for_termination(0)).to be true
    ensure
      release&.set
    end

    it 'shuts down immediately when never started' do
      wakeup_ios = [
        executor.instance_variable_get(:@wakeup_reader),
        executor.instance_variable_get(:@wakeup_writer),
      ]

      executor.shutdown

      expect(executor.shutdown?).to be true
      expect(executor.wait_for_termination(1)).to be true
      expect(wakeup_ios).to all(be_closed)
    end
  end

  describe '#kill' do
    it 'completes cancellation after Ruby CPU work returns control' do
      started = Concurrent::Event.new
      release = Concurrent::AtomicBoolean.new(false)
      executor.post do
        started.set
        loop { break if release.true? }
      end
      expect(started.wait(5)).to be true
      executor.kill
      # Some Ruby/Async versions defer the interrupt until the job yields.
      executor.wait_for_termination(0.01)
      release.make_true
      expect(executor.wait_for_termination(5)).to be true
    ensure
      release&.make_true
    end

    it 'stops the reactor without waiting for tasks' do
      wakeup_ios = [
        executor.instance_variable_get(:@wakeup_reader),
        executor.instance_variable_get(:@wakeup_writer),
      ]
      started = Concurrent::CountDownLatch.new(5)
      completed = Concurrent::Array.new
      5.times do
        executor.post do
          started.count_down
          sleep 60
        end
      end
      expect(started.wait(5)).to be true
      executor.post { completed << :queued }
      executor.kill
      expect(executor.wait_for_termination(5)).to be true
      expect(executor.shutdown?).to be true
      expect(wakeup_ios).to all(be_closed)
      expect(completed).to be_empty
      expect(executor.ready_worker_count).to eq 5
    end

    it 'closes resources when killed before the reactor starts' do
      entered = Concurrent::Event.new
      release = Concurrent::Event.new
      allow(executor).to receive(:run_reactor).and_wrap_original do |original|
        entered.set
        release.wait(5)
        original.call
      end
      executor.post { raise 'must not run' }
      expect(entered.wait(5)).to be true
      executor.kill
      release.set
      expect(executor.wait_for_termination(5)).to be true
      expect(executor.instance_variable_get(:@wakeup_reader)).to be_closed
      expect(executor.instance_variable_get(:@wakeup_writer)).to be_closed
    ensure
      release&.set
    end
  end

  describe 'forking' do
    it 'replaces inherited work and pipes without affecting the parent' do
      skip 'fork is unavailable' unless Process.respond_to?(:fork)

      started = Concurrent::CountDownLatch.new(5)
      release = Concurrent::Event.new
      completed = Concurrent::Array.new
      5.times do
        executor.post do
          started.count_down
          release.wait(10)
        end
      end
      expect(started.wait(5)).to be true
      executor.post { completed << :parent }
      old_reader = executor.instance_variable_get(:@wakeup_reader)
      result_reader, result_writer = IO.pipe
      pid = fork do
        result_reader.close
        executor.post { completed << :child }
        executor.shutdown
        success = executor.wait_for_termination(5) && completed == [:child] && old_reader.closed?
        result_writer.write(success ? 'ok' : 'failed')
        result_writer.close
        exit! 0
      end
      result_writer.close
      expect(result_reader.wait_readable(10)).to be_truthy
      expect(result_reader.read).to eq 'ok'
      Process.wait(pid)
      pid = nil
      expect(old_reader).not_to be_closed
      release.set
      executor.shutdown
      expect(executor.wait_for_termination(5)).to be true
      expect(completed).to eq [:parent]
    ensure
      release&.set
      result_reader&.close
      result_writer&.close unless result_writer&.closed?
      if pid
        Process.kill('KILL', pid)
        Process.wait(pid)
      end
    end
  end
end
