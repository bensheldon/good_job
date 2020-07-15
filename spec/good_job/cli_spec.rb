# frozen_string_literal: true
require 'rails_helper'
require 'good_job/cli'

RSpec.describe GoodJob::CLI do
  let(:scheduler_mock) { instance_double GoodJob::Scheduler, shutdown?: false, shutdown: nil }
  let(:env) { {} }
  let(:args) { [] }

  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("spec/dummy/config/environment.rb")
    allow(GoodJob::Scheduler).to receive(:new).and_return scheduler_mock
  end

  describe '#start' do
    it 'initializes a scheduler' do
      allow(GoodJob::Scheduler).to receive(:new).and_call_original
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})

      expect do
        cli.start
      end.to output.to_stdout

      expect(GoodJob::Scheduler).to have_received(:new)
    end

    it 'can gracefully shut down on INT signal' do
      cli = described_class.new([], {}, {})

      cli_thread = Concurrent::Promises.future do
        expect do
          cli.start
        end.to output(/finished, exiting/).to_stdout
      end

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

        expect do
          cli.start
        end.to output.to_stdout

        expect(GoodJob::Scheduler).to have_received(:new).with(a_kind_of(GoodJob::Job::Performer), pool_options: { max_threads: 4 }, timer_options: {})
      end
    end

    describe 'queues' do
      before { allow(Kernel).to receive(:loop) }

      around { |example| freeze_time { example.run } }

      it 'defaults to --queues, GOOD_JOB_QUEUES, all queues' do
        cli = described_class.new([], { queues: 'mice,elephant' }, {})
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_QUEUES' => 'elephant,whale' })

        allow(GoodJob::Scheduler).to receive(:new) do |performer, _options|
          performer_query = performer.instance_variable_get(:@query)
          expect(performer_query.to_sql).to eq GoodJob::Job.where(queue_name: %w[mice elephant]).only_scheduled.priority_ordered.to_sql

          scheduler_mock
        end

        expect { cli.start }.to output.to_stdout
        expect(GoodJob::Scheduler).to have_received(:new).with(a_kind_of(GoodJob::Job::Performer), a_kind_of(Hash))
      end
    end
  end
end
