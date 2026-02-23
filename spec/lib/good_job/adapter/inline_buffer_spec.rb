# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::Adapter::InlineBuffer do
  around do |example|
    perform_good_job_inline do
      example.run
    end
  end

  before do
    stub_const 'SuccessJob', (Class.new(ActiveJob::Base) do
      def perform
        true
      end
    end)

    stub_const 'ErrorJob', (Class.new(ActiveJob::Base) do
      def perform
        raise 'Error'
      end
    end)
  end

  context "when using enqueue_all" do
    it "defers enqueue_all" do
      Rails.application.executor.wrap do
        buffer = described_class.capture do
          SuccessJob.queue_adapter.enqueue_all([SuccessJob.new, SuccessJob.new])
          expect(GoodJob::Job.count).to eq 2
          expect(GoodJob::Job.all).to all have_attributes(finished_at: nil)
        end

        buffer.call

        expect(GoodJob::Job.all).to all have_attributes(finished_at: be_present)
      end
    end

    it "defers enqueue_all with errors" do
      Rails.application.executor.wrap do
        buffer = described_class.capture do
          ErrorJob.queue_adapter.enqueue_all([ErrorJob.new, SuccessJob.new])
          expect(GoodJob::Job.count).to eq 2
          expect(GoodJob::Job.all).to all have_attributes(finished_at: nil)
        end

        expect { buffer.call }.to raise_error(/Error/)
        expect(GoodJob::Job.find_by(job_class: "ErrorJob")).to have_attributes(finished_at: be_present, error: be_present, error_event: 'unhandled')
        expect(GoodJob::Job.find_by(job_class: "SuccessJob")).to have_attributes(finished_at: nil)
      end
    end
  end

  context "when using enqueue" do
    it "defers inline enqueued jobs" do
      Rails.application.executor.wrap do
        buffer = described_class.capture do
          SuccessJob.perform_later
          expect(GoodJob::Job.count).to eq 1
        end
        buffer.call

        expect(GoodJob::Job.count).to eq 1
        expect(GoodJob::Job.first).to have_attributes(finished_at: be_present)
      end
    end

    it "defers inline enqueued jobs with errors" do
      Rails.application.executor.wrap do
        buffer = described_class.capture do
          ErrorJob.perform_later
          expect(GoodJob::Job.count).to eq 1
        end

        expect { buffer.call }.to raise_error(/Error/)
        expect(GoodJob::Job.first).to have_attributes(finished_at: be_present, error: be_present, error_event: 'unhandled')
      end
    end
  end
end
