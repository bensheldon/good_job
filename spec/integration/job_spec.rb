# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job' do
  let(:inline_adapter) { GoodJob::Adapter.new(execution_mode: :inline) }

  describe 'job status after retry' do
    before do
      ActiveJob::Base.queue_adapter = inline_adapter

      stub_const "TestJob", (Class.new(ActiveJob::Base) do
        retry_on StandardError, wait: 0, attempts: Float::INFINITY

        def perform
          raise 'failing' if executions < 2
        end
      end)
    end

    it 'retries a job once and then succeeds' do
      TestJob.perform_later

      job = GoodJob::Job.order(:created_at).last
      executions = job.discrete_executions.order(:created_at).to_a
      expect(executions.size).to eq 2
      expect(executions.first.status).to eq :discarded
      expect(executions.last.status).to eq :succeeded
      # expect(job.status).to eq :succeeded
      expect(job.performed_at).to be_present
      expect(job.finished_at).to be_present
    end
  end
end
