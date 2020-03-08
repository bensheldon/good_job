# frozen_string_literal: true
require 'rails_helper'
require 'good_job/cli'

RSpec.describe GoodJob::CLI do
  let(:scheduler_mock) { instance_double GoodJob::Scheduler, shutdown?: false, shutdown: nil }

  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("spec/dummy/config/environment.rb")

    allow(GoodJob::Scheduler).to receive(:new).and_return scheduler_mock
  end

  describe '#start' do
    it 'initializes a scheduler' do
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})

      expect do
        cli.start
      end.to output.to_stdout

      expect(GoodJob::Scheduler).to have_received(:new)
      expect(scheduler_mock).to have_received(:shutdown)
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
  end
end
