# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::CLI do
  let(:capsule_mock) { instance_double GoodJob::Capsule, start: nil, shutdown?: false, shutdown: nil, idle?: false }

  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("demo/config/environment.rb")
    stub_const 'GoodJob::CLI::SHUTDOWN_EVENT_TIMEOUT', 0.1
    allow(GoodJob).to receive_messages(configuration: GoodJob::Configuration.new({}), capsule: capsule_mock)
  end

  describe '#start' do
    it 'starts and stops a capsule' do
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})
      cli.start

      expect(capsule_mock).to have_received(:start)
      expect(capsule_mock).to have_received(:shutdown)
    end

    it 'can gracefully shut down on INT signal' do
      cli = described_class.new([], {}, {})

      cli_thread = Concurrent::Promises.future { cli.start }
      sleep_until { cli.instance_variable_get(:@stop_good_job_executable) }

      Process.kill 'INT', Process.pid # Send the signal to ourselves

      sleep_until { cli_thread.fulfilled? }

      expect(capsule_mock).to have_received(:shutdown)
    end

    describe 'configuration options' do
      before do
        allow(Kernel).to receive(:loop)
      end

      it 'merges options into GoodJob.configuration' do
        cli = described_class.new([], { poll_interval: 5 }, {})
        cli.start

        expect(GoodJob.configuration.poll_interval).to eq 5
      end
    end

    describe 'idle-timeout' do
      it 'exits when the capsule is idle' do
        allow(capsule_mock).to receive(:idle?).and_return true

        cli = described_class.new([], { idle_timeout: 1 }, {})
        cli.start

        expect(capsule_mock).to have_received(:idle?).with(1)
        expect(capsule_mock).to have_received(:shutdown)
      end
    end

    describe 'probe-handler' do
      let(:probe_server) { instance_double GoodJob::ProbeServer, start: nil, stop: nil }

      before do
        allow(Kernel).to receive(:loop)
        allow(GoodJob::ProbeServer).to receive(:new).and_return probe_server
      end

      context 'when a port and handler are specified' do
        it 'starts a ProbeServer with the specified port and a "nil" app' do
          cli = described_class.new([], { probe_port: 3838, probe_handler: "webrick" }, {})
          cli.start

          expect(GoodJob::ProbeServer).to have_received(:new).with(app: nil, port: 3838, handler: :webrick)
          expect(probe_server).to have_received(:start)
          expect(probe_server).to have_received(:stop)
        end
      end
    end

    describe 'probe-port' do
      let(:probe_server) { instance_double GoodJob::ProbeServer, start: nil, stop: nil }

      before do
        allow(Kernel).to receive(:loop)
        allow(GoodJob::ProbeServer).to receive(:new).and_return probe_server
      end

      context 'when a port is specified' do
        it 'starts a ProbeServer with the specified port and a "nil" app' do
          cli = described_class.new([], { probe_port: 3838 }, {})
          cli.start

          expect(GoodJob::ProbeServer).to have_received(:new).with(app: nil, port: 3838, handler: nil)
          expect(probe_server).to have_received(:start)
          expect(probe_server).to have_received(:stop)
        end
      end

      context 'when a port and an app are set in the Rails configuration' do
        it 'starts a ProbesServer with the configured port and app' do
          app_mock = instance_double(Proc, call: nil)
          configuration_mock = instance_double(
            GoodJob::Configuration,
            probe_app: app_mock,
            probe_port: 3838,
            probe_handler: nil,
            options: {},
            daemonize?: false,
            cluster?: false,
            subprocesses: 0,
            shutdown_timeout: 100,
            idle_timeout: 100
          )
          allow(GoodJob).to receive_messages(configuration: configuration_mock)
          cli = described_class.new([], [], {})
          cli.start

          expect(GoodJob::ProbeServer).to have_received(:new).with(app: app_mock, port: 3838, handler: nil)
          expect(probe_server).to have_received(:start)
          expect(probe_server).to have_received(:stop)
        end
      end

      context 'when a port is not specified' do
        it 'does not start a ProbeServer' do
          cli = described_class.new([], {}, {})
          cli.start

          expect(GoodJob::ProbeServer).not_to have_received(:new)
          expect(probe_server).not_to have_received(:start)
          expect(probe_server).not_to have_received(:stop)
        end
      end
    end

    describe 'systemd support' do
      let(:systemd) { instance_double GoodJob::SystemdService, start: nil, stop: nil }

      before do
        allow(GoodJob::SystemdService).to receive(:new).and_return systemd
      end

      it 'notifies systemd about starting and stopping' do
        cli = described_class.new([], {}, {})

        cli_thread = Concurrent::Promises.future { cli.start }
        sleep_until { cli.instance_variable_get(:@stop_good_job_executable) }
        expect(GoodJob::SystemdService).to have_received(:new)
        expect(systemd).to have_received(:start)
        expect(systemd).not_to have_received(:stop)

        Process.kill 'INT', Process.pid # Send the signal to ourselves

        sleep_until { cli_thread.fulfilled? }
        expect(systemd).to have_received(:stop)
      end
    end

    describe 'cluster mode' do
      context 'when subprocesses is set and fork is available' do
        let(:supervisor) { instance_double GoodJob::Supervisor, start: nil }

        before do
          allow(GoodJob).to receive(:configuration).and_return(GoodJob::Configuration.new({ subprocesses: 2 }))
          allow(Process).to receive(:respond_to?).and_call_original
          allow(Process).to receive(:respond_to?).with(:fork).and_return(true)
          allow(GoodJob::Supervisor).to receive(:new).and_return(supervisor)
        end

        it 'notifies systemd when the supervisor begins shutting down, not once it has finished' do
          systemd = instance_double GoodJob::SystemdService, start: nil, stopping: nil, stop: nil
          allow(GoodJob::SystemdService).to receive(:new).and_return systemd
          # The supervisor blocks until every subprocess has drained, so it hands
          # back the start of the shutdown via this callback.
          allow(supervisor).to receive(:start) { |on_shutdown:| on_shutdown.call }

          cli = described_class.new([], {}, {})
          cli.start

          expect(systemd).to have_received(:stopping)
        end

        it 'starts a supervisor instead of the capsule' do
          cli = described_class.new([], {}, {})
          cli.start

          expect(GoodJob::Supervisor).to have_received(:new)
          expect(supervisor).to have_received(:start)
          expect(capsule_mock).not_to have_received(:start)
        end

        context 'when an idle_timeout is also configured' do
          before do
            allow(GoodJob).to receive(:configuration).and_return(GoodJob::Configuration.new({ subprocesses: 2, idle_timeout: 30 }))
          end

          it 'warns that idle_timeout is unsupported rather than silently ignoring it' do
            allow(GoodJob.logger).to receive(:warn)

            cli = described_class.new([], {}, {})
            cli.start

            expect(GoodJob.logger).to have_received(:warn).with(/idle_timeout is not supported in cluster mode/)
            expect(supervisor).to have_received(:start)
          end
        end

        it 'does not warn about idle_timeout when none is configured' do
          allow(GoodJob.logger).to receive(:warn)

          cli = described_class.new([], {}, {})
          cli.start

          expect(GoodJob.logger).not_to have_received(:warn).with(/idle_timeout/)
        end
      end

      context 'when subprocesses is set but fork is unavailable' do
        let(:configuration) { GoodJob::Configuration.new({ subprocesses: 2 }) }

        before do
          allow(Kernel).to receive(:loop)
          allow(GoodJob).to receive(:configuration).and_return(configuration)
          allow(Process).to receive(:respond_to?).and_call_original
          allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
        end

        it 'warns and runs the capsule in a single process' do
          allow(GoodJob.logger).to receive(:warn)

          cli = described_class.new([], {}, {})
          cli.start

          expect(GoodJob.logger).to have_received(:warn).with(/does not support forking/)
          expect(capsule_mock).to have_received(:start)
        end

        context 'when the queues are pipe-delimited subprocess pools' do
          let(:configuration) { GoodJob::Configuration.new({ queues: 'elephant:2|mice:3' }) }

          it 'warns that every pool will run in this one process' do
            allow(GoodJob.logger).to receive(:warn)

            cli = described_class.new([], {}, {})
            cli.start

            expect(GoodJob.logger).to have_received(:warn).with(/every queue pool in a single process/)
            expect(capsule_mock).to have_received(:start)
          end
        end
      end
    end
  end

  describe '#cleanup_preserved_jobs' do
    let!(:recent_job) { GoodJob::Job.create!(active_job_id: SecureRandom.uuid, finished_at: 12.hours.ago) }
    let!(:old_unfinished_job) { GoodJob::Job.create!(active_job_id: SecureRandom.uuid, scheduled_at: 2.days.ago, finished_at: nil) }
    let!(:old_finished_job) { GoodJob::Job.create!(active_job_id: SecureRandom.uuid, finished_at: 36.hours.ago) }

    it 'destroys finished jobs' do
      cli = described_class.new([], { before_seconds_ago: 24.hours.to_i }, {})

      cli.cleanup_preserved_jobs

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end
  end
end
