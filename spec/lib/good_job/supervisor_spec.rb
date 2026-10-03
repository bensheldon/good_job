# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Supervisor do
  let(:configuration) { GoodJob::Configuration.new({ subprocesses: 2 }) }
  let(:supervisor) { described_class.new(configuration) }

  def track_subprocess(pid)
    supervisor.instance_variable_get(:@subprocesses)[pid] = GoodJob::Supervisor::SubprocessHandle.new(pid: pid, recipe: configuration)
  end

  describe GoodJob::Supervisor::SubprocessHandle do
    it 'stores the pid, index, recipe, and restart count' do
      handle = described_class.new(pid: 123, index: 1, recipe: :recipe, restart_count: 2)

      expect(handle.pid).to eq(123)
      expect(handle.index).to eq(1)
      expect(handle.recipe).to eq(:recipe)
      expect(handle.restart_count).to eq(2)
    end

    it 'reports a small, non-negative uptime immediately after being forked' do
      handle = described_class.new(pid: 123, recipe: :recipe)

      expect(handle.uptime).to be >= 0
      expect(handle.uptime).to be < 1
    end

    describe '#connected?' do
      let(:handle) { described_class.new(pid: 1, recipe: :recipe) }
      let(:now) { GoodJob::Supervisor.monotonic }

      it 'is not connected until it has reported readiness' do
        expect(handle.connected?(now, 15)).to be false
      end

      it 'is connected within the staleness window of a readiness report' do
        handle.mark_ready(now - 5)

        expect(handle.connected?(now, 15)).to be true
      end

      it 'is not connected once the readiness report is older than the window' do
        handle.mark_ready(now - 20)

        expect(handle.connected?(now, 15)).to be false
      end
    end
  end

  describe '#backoff_delay' do
    it 'does not delay a first fast replacement' do
      expect(supervisor.send(:backoff_delay, 0)).to eq(0)
      expect(supervisor.send(:backoff_delay, 1)).to eq(0)
    end

    it 'backs off exponentially once a subprocess keeps crashing' do
      expect(supervisor.send(:backoff_delay, 2)).to eq(1)
      expect(supervisor.send(:backoff_delay, 3)).to eq(2)
      expect(supervisor.send(:backoff_delay, 4)).to eq(4)
    end

    it 'caps the delay at MAX_BACKOFF_DELAY' do
      expect(supervisor.send(:backoff_delay, 50)).to eq(GoodJob::Supervisor::MAX_BACKOFF_DELAY)
    end
  end

  describe '#backoff' do
    def elapsed
      started_at = described_class.monotonic
      yield
      described_class.monotonic - started_at
    end

    it 'waits out the delay when no shutdown signal is pending' do
      duration = elapsed { supervisor.send(:backoff, 2) } # a 1 second delay

      expect(duration).to be >= 1
      expect(supervisor.instance_variable_get(:@stopped)).to be false
    end

    it 'does not wait when a shutdown signal arrived before the delay began' do
      # The signal's self-pipe wakeup is discarded by #backoff, so the queued
      # signal itself is what must cut the wait short.
      supervisor.instance_variable_get(:@received_signals) << 'TERM'

      duration = elapsed { supervisor.send(:backoff, 50) } # a 30 second delay

      expect(duration).to be < 1
      expect(supervisor.instance_variable_get(:@stopped)).to be true
    end
  end

  describe '#restart_count_after' do
    it 'increments the count for a subprocess that exited before it was healthy' do
      handle = GoodJob::Supervisor::SubprocessHandle.new(pid: 1, recipe: :r, restart_count: 2)
      allow(handle).to receive(:uptime).and_return(GoodJob::Supervisor::MIN_HEALTHY_UPTIME - 1)

      expect(supervisor.send(:restart_count_after, handle)).to eq(3)
    end

    it 'resets the count once a subprocess has run long enough to be healthy' do
      handle = GoodJob::Supervisor::SubprocessHandle.new(pid: 1, recipe: :r, restart_count: 5)
      allow(handle).to receive(:uptime).and_return(GoodJob::Supervisor::MIN_HEALTHY_UPTIME + 1)

      expect(supervisor.send(:restart_count_after, handle)).to eq(0)
    end
  end

  describe '#escalation_timeout' do
    it 'gives a positive drain timeout an extra grace period before SIGKILL' do
      expect(supervisor.send(:escalation_timeout, 10)).to eq(10 + GoodJob::Supervisor::SHUTDOWN_GRACE)
    end

    it 'does not add grace to an immediate (0) shutdown' do
      expect(supervisor.send(:escalation_timeout, 0)).to eq(0)
    end
  end

  describe '#running? and #started?' do
    it 'is neither running nor started before the supervisor starts' do
      expect(supervisor.running?).to be false
      expect(supervisor.started?).to be false
    end

    context 'when running with every configured subprocess alive' do
      before do
        supervisor.instance_variable_set(:@supervisor_pid, Process.pid)
        track_subprocess(111)
        track_subprocess(222)
      end

      it 'is running and started' do
        expect(supervisor.running?).to be true
        expect(supervisor.started?).to be true
      end

      it 'is no longer started once a subprocess is missing' do
        supervisor.instance_variable_get(:@subprocesses).delete(111)
        expect(supervisor.started?).to be false
      end

      it 'is neither running nor started once stopped' do
        supervisor.instance_variable_set(:@stopped, true)
        expect(supervisor.running?).to be false
        expect(supervisor.started?).to be false
      end
    end
  end

  describe '#connected?' do
    def handle(pid)
      supervisor.instance_variable_get(:@subprocesses)[pid]
    end

    before do
      supervisor.instance_variable_set(:@supervisor_pid, Process.pid)
      track_subprocess(111)
      track_subprocess(222)
    end

    it 'is connected once every subprocess has recently reported readiness' do
      handle(111).mark_ready(described_class.monotonic)
      handle(222).mark_ready(described_class.monotonic)

      expect(supervisor.connected?).to be true
    end

    it 'is not connected while a subprocess has never reported readiness' do
      handle(111).mark_ready(described_class.monotonic)

      expect(supervisor.connected?).to be false
    end

    it 'is not connected once a subprocess readiness report has gone stale' do
      handle(111).mark_ready(described_class.monotonic)
      handle(222).mark_ready(described_class.monotonic - described_class::CONNECTED_TIMEOUT - 1)

      expect(supervisor.connected?).to be false
    end

    it 'is not connected unless the supervisor is started' do
      handle(111).mark_ready(described_class.monotonic)
      handle(222).mark_ready(described_class.monotonic)
      supervisor.instance_variable_get(:@subprocesses).delete(111)

      expect(supervisor.connected?).to be false
    end
  end

  describe '#start_probe_server' do
    let(:configuration) { GoodJob::Configuration.new({ subprocesses: 2, probe_port: 7010 }) }

    before { allow(GoodJob::ProbeServer).to receive(:new).and_return(instance_double(GoodJob::ProbeServer, start: nil)) }

    it 'serves the cluster health check app' do
      supervisor.send(:start_probe_server)

      expect(GoodJob::ProbeServer).to have_received(:new).with(hash_including(port: 7010, app: an_instance_of(Rack::Builder)))
    end

    it 'serves a configured probe_app instead of the cluster health check app' do
      probe_app = ->(_env) { [200, {}, ["custom"]] }
      allow(configuration).to receive(:probe_app).and_return(probe_app)

      supervisor.send(:start_probe_server)

      expect(GoodJob::ProbeServer).to have_received(:new).with(hash_including(app: probe_app))
    end

    it 'does not start a probe server when no port is configured' do
      allow(configuration).to receive(:probe_port).and_return(nil)

      supervisor.send(:start_probe_server)

      expect(GoodJob::ProbeServer).not_to have_received(:new)
    end
  end

  describe '#supervise' do
    it 'invokes the on_shutdown callback before the subprocesses are told to drain' do
      supervisor.instance_variable_set(:@stopped, true)
      events = []
      allow(supervisor).to receive(:terminate_subprocesses) { events << :terminate }

      supervisor.send(:supervise, on_shutdown: -> { events << :on_shutdown })

      expect(events).to eq(%i[on_shutdown terminate])
    end

    it 'reports an error from the callback and still shuts down' do
      supervisor.instance_variable_set(:@stopped, true)
      allow(GoodJob).to receive(:_on_thread_error)
      allow(supervisor).to receive(:terminate_subprocesses)

      supervisor.send(:supervise, on_shutdown: -> { raise "boom" })

      expect(GoodJob).to have_received(:_on_thread_error).with(an_instance_of(RuntimeError))
      expect(supervisor).to have_received(:terminate_subprocesses)
    end
  end
end
