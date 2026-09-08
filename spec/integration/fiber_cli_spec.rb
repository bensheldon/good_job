# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe 'Fiber CLI shutdown', :fiber_isolation, :requires_async do
  it 'exits promptly on TERM while a fiber job blocks and allows later recovery' do
    stub_const 'CliInterruptedJob', Class.new(ActiveJob::Base) {
      def perform
      end
    }
    CliInterruptedJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    GoodJob.preserve_job_records = true
    job = CliInterruptedJob.perform_later

    Dir.mktmpdir('good-job-cli') do |directory|
      log_path = File.join(directory, 'worker.log')
      script = <<~WORKER
        $stdout.sync = true
        require 'good_job/cli'
        GoodJob::CLI.within_exe = true
        require './config/environment'
        GoodJob.preserve_job_records = true
        class CliInterruptedJob < ActiveJob::Base
          def perform
            raise 'expected a fiber worker' unless Fiber.scheduler
            puts 'JOB_STARTED'
            sleep 60
          end
        end
        # Observe readiness only after the real CLI has installed its TERM trap.
        module TrapReadiness
          def trap(signal, &block)
            super.tap { puts 'TERM_READY' if signal == 'TERM' }
          end
        end
        GoodJob::CLI.prepend(TrapReadiness)
        GoodJob::CLI.start(%w[start --fibers 1 --shutdown-timeout 0.5 --poll-interval 0.1])
      WORKER
      pid = Process.spawn(
        { 'GOOD_JOB_FIBERS' => '1', 'GOOD_JOB_EXECUTION_MODE' => 'external', 'GOOD_JOB_ENABLE_CRON' => 'false',
          'GOOD_JOB_LOCK_STRATEGY' => 'advisory', 'RAILS_ENV' => 'test', 'CI' => 'true',
          'DATABASE_URL' => ENV.fetch('DATABASE_URL', 'postgresql://localhost/good_job_test') },
        RbConfig.ruby, '-rbundler/setup', '-e', script,
        chdir: Rails.root.to_s, out: log_path, err: [:child, :out]
      )
      begin
        wait_until(max: 20) do
          expect(File.read(log_path)).to include('JOB_STARTED', 'TERM_READY')
        end
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Process.kill('TERM', pid)
        status = nil
        wait_until(max: 10) do
          result = Process.waitpid2(pid, Process::WNOHANG)
          status = result.last if result
          expect(status).to be_present, File.read(log_path)
        end
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to be < 10
        expect(status).to be_success, File.read(log_path)
        expect(GoodJob::Job.find(job.job_id).finished_at).to be_nil

        scheduler = GoodJob::Scheduler.new(GoodJob::JobPerformer.new('*'), fibers: 1)
        scheduler.create_thread
        wait_until(max: 15) { expect(GoodJob::Job.find(job.job_id).finished_at).to be_present }
        executions = GoodJob::Execution.where(active_job_id: job.job_id)
        expect(executions.count).to eq 2
        expect(executions.where.not(error: nil).count).to eq 1
      ensure
        scheduler&.shutdown
        unless status
          Process.kill('KILL', pid)
          Process.waitpid(pid)
        end
      end
    end
  end
end
