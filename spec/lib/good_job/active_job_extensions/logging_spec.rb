# spec/lib/good_job/active_job_extensions/logging_spec.rb

# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Logging do
  before do
    # freeze_time
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Logging

      def perform
        logger.info "Hello, world!"
        logger.debug "Debug level!"
        logger.tagged("TAG") { logger.info "Tagged!" }
      end
    end)
  end

  # very naive test case, please modify based on implementation
  describe '.logs' do
    it 'stores the logs from the job in a tuple of execution ID and log' do
      active_job = TestJob.perform_later
      GoodJob.perform_inline

      job_log = described_class::LogDevice.logs
      # I expect this tuple would be replaced with a better object eventually, but that can be deferred to later checkpoints.
      expect(job_log).to eq([
                              [active_job.provider_job_id, 'Hello, world!'],
                              [active_job.provider_job_id, 'Debug level!'],
                              [active_job.provider_job_id, '[TAG] Tagged!'],
                            ])
    end
  end
end
