# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::Bulk do
  before do
    stub_const 'TestJob', Class.new(ActiveJob::Base)
    TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  describe '.enqueue' do
    it 'enqueues multiple jobs at once' do
      described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(GoodJob::Job.count).to eq 2
    end

    it 'does not enqueue jobs if there is an error' do
      expect do
        described_class.enqueue do
          TestJob.perform_later
          TestJob.perform_later
          raise 'error'
        end
      end.to raise_error('error')

      expect(GoodJob::Job.count).to eq 0
    end

    describe 'wrap:' do
      it 'wraps the bulk enqueuing' do
        wrapped_jobs = nil
        wrapper = lambda do |jobs, &block|
          wrapped_jobs = jobs
          block.call
        end

        described_class.enqueue(wrap: wrapper) do
          TestJob.perform_later
          TestJob.perform_later
        end

        expect(GoodJob::Job.count).to eq 2
        expect(wrapped_jobs.count).to eq 2
      end
    end
  end
end
