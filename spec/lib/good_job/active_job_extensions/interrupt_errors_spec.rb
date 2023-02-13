# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::InterruptErrors do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::InterruptErrors

      def perform
      end
    end)
  end

  context 'when a dequeued job has a performed_at but no finished_at' do
    before do
      active_job = TestJob.perform_later
      GoodJob::Execution.find_by(active_job_id: active_job.job_id).update!(performed_at: Time.current)
    end

    it 'raises a GoodJob::InterruptError' do
      expect { GoodJob.perform_inline }.to raise_error(GoodJob::InterruptError)
    end

    it 'is rescuable' do
      TestJob.retry_on GoodJob::InterruptError

      expect { GoodJob.perform_inline }.not_to raise_error
      expect(GoodJob::Execution.count).to eq(2)

      job = GoodJob::Job.first
      expect(job.executions.first.error).to start_with 'GoodJob::InterruptError: Interrupted after starting perform at'
    end
  end

  context 'when dequeued job does not have performed at' do
    before do
      TestJob.perform_later
    end

    it 'does not raise' do
      expect { GoodJob.perform_inline }.not_to raise_error
    end
  end
end
