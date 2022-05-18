# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::CLI do
  let(:scheduler_mock) { instance_double GoodJob::Scheduler, shutdown?: false, shutdown: nil }
  let(:env) { {} }
  let(:args) { [] }

  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("spec/test_app/config/environment.rb")
    allow(GoodJob::Scheduler).to receive(:new).and_return scheduler_mock
  end

  describe '#start' do
    it 'initializes a scheduler' do
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})
      cli.start

      expect(GoodJob::Scheduler).to have_received(:new)
    end

    it 'can gracefully shut down on INT signal' do
      cli = described_class.new([], {}, {})

      cli_thread = Concurrent::Promises.future { cli.start }
      sleep_until { cli.instance_variable_get(:@stop_good_job_executable) == false }

      Process.kill 'INT', Process.pid # Send the signal to ourselves

      sleep_until { cli_thread.fulfilled? }

      expect(GoodJob::Scheduler).to have_received(:new)
      expect(scheduler_mock).to have_received(:shutdown)
    end

    describe 'max threads' do
      it 'defaults to --max_threads, GOOD_JOB_MAX_THREADS, RAILS_MAX_THREADS, database connection pool size' do
        allow(Kernel).to receive(:loop)

        cli = described_class.new([], { max_threads: 4 }, {})
        stub_const 'ENV', ENV.to_hash.merge({ 'RAILS_MAX_THREADS' => 3, 'GOOD_JOB_MAX_THREADS' => 2 })
        allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(1)

        cli.start

        expect(GoodJob::Scheduler).to have_received(:new).with(
          a_kind_of(GoodJob::JobPerformer),
          max_threads: 4,
          max_cache: GoodJob::Configuration::DEFAULT_MAX_CACHE,
          warm_cache_on_initialize: true,
          cleanup_interval_seconds: nil,
          cleanup_interval_jobs: nil
        )
      end
    end

    describe 'queues' do
      before { allow(Kernel).to receive(:loop) }

      around { |example| freeze_time { example.run } }

      it 'defaults to --queues, GOOD_JOB_QUEUES, all queues' do
        cli = described_class.new([], { queues: 'mice,elephant' }, {})
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_QUEUES' => 'elephant,whale' })

        performer = nil
        allow(GoodJob::Scheduler).to receive(:new) do |performer_arg, _options|
          performer = performer_arg
          scheduler_mock
        end

        cli.start
        expect(GoodJob::Scheduler).to have_received(:new).with(a_kind_of(GoodJob::JobPerformer), a_kind_of(Hash))

        performer_query = performer.send(:job_query)
        expect(performer_query.to_sql).to eq GoodJob::Execution.where(queue_name: %w[mice elephant]).to_sql
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
