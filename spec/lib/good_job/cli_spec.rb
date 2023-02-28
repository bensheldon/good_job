# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::CLI do
  let(:capsule_mock) { instance_double GoodJob::Capsule, start: nil, shutdown?: false, shutdown: nil }

  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("spec/test_app/config/environment.rb")
    allow(GoodJob).to receive(:configuration).and_return(GoodJob::Configuration.new({}))
    allow(GoodJob::Capsule).to receive(:new).and_return capsule_mock
  end

  describe '#start' do
    it 'initializes a capsule' do
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})
      cli.start

      expect(GoodJob::Capsule).to have_received(:new)
    end

    it 'can gracefully shut down on INT signal' do
      cli = described_class.new([], {}, {})

      cli_thread = Concurrent::Promises.future { cli.start }
      sleep_until { cli.instance_variable_get(:@stop_good_job_executable) == false }

      Process.kill 'INT', Process.pid # Send the signal to ourselves

      sleep_until { cli_thread.fulfilled? }

      expect(GoodJob::Capsule).to have_received(:new)
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

    describe 'probe-port' do
      let(:probe_server) { instance_double GoodJob::ProbeServer, start: nil, stop: nil }

      before do
        allow(Kernel).to receive(:loop)
        allow(GoodJob::ProbeServer).to receive(:new).and_return probe_server
      end

      it 'starts a ProbeServer' do
        cli = described_class.new([], { probe_port: 3838 }, {})
        cli.start

        expect(GoodJob::ProbeServer).to have_received(:new).with(port: 3838)
        expect(probe_server).to have_received(:start)
        expect(probe_server).to have_received(:stop)
      end
    end
  end

  describe '#cleanup_preserved_jobs' do
    let!(:recent_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 12.hours.ago) }
    let!(:old_unfinished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, scheduled_at: 2.days.ago, finished_at: nil) }
    let!(:old_finished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 36.hours.ago) }

    it 'destroys finished jobs' do
      cli = described_class.new([], { before_seconds_ago: 24.hours.to_i }, {})

      cli.cleanup_preserved_jobs

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end
  end
end
