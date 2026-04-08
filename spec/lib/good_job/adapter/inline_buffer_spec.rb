# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::Adapter::InlineBuffer do
  before do
    stub_const 'SuccessJob', (Class.new(ActiveJob::Base) do
      def perform
        true
      end
    end)
    SuccessJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)

    stub_const 'ErrorJob', (Class.new(ActiveJob::Base) do
      def perform
        raise 'Error'
      end
    end)
    ErrorJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  shared_examples 'inline enqueue with lock strategy' do |strategy|
    around do |example|
      original = GoodJob.configuration.options[:lock_strategy]
      GoodJob.configuration.options[:lock_strategy] = strategy
      example.run
    ensure
      if original.nil?
        GoodJob.configuration.options.delete(:lock_strategy)
      else
        GoodJob.configuration.options[:lock_strategy] = original
      end
    end

    let(:captured_lock_types) { [] }

    before do
      captured = captured_lock_types
      stub_const 'LockCapturingJob', (Class.new(ActiveJob::Base) do
        define_method(:perform) { captured << GoodJob::CurrentThread.job&.lock_type }
      end)
      LockCapturingJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
    end

    it "enqueue executes with lock_type #{strategy} and clears lock columns after execution" do
      Rails.application.executor.wrap do
        LockCapturingJob.perform_later
      end

      expect(captured_lock_types).to eq([strategy.to_s])
      expect(GoodJob::Job.last).to have_attributes(lock_type: nil, locked_by_id: nil, finished_at: be_present)
    end

    it "enqueue_all executes with lock_type #{strategy} and clears lock columns after execution" do
      Rails.application.executor.wrap do
        LockCapturingJob.queue_adapter.enqueue_all([LockCapturingJob.new, LockCapturingJob.new])
      end

      expect(captured_lock_types).to all eq(strategy.to_s)
      expect(captured_lock_types.size).to eq 2
      expect(GoodJob::Job.all).to all have_attributes(lock_type: nil, locked_by_id: nil, finished_at: be_present)
    end
  end

  it_behaves_like 'inline enqueue with lock strategy', :skiplocked
  it_behaves_like 'inline enqueue with lock strategy', :hybrid

  context 'when lock_type column does not exist (pre-migration)' do
    before { allow(GoodJob::Job).to receive(:lock_type_column_exists?).and_return(false) }

    [:skiplocked, :hybrid].each do |strategy|
      it "falls back to advisory lock behavior for #{strategy} strategy via enqueue" do
        GoodJob.configuration.options[:lock_strategy] = strategy
        Rails.application.executor.wrap { SuccessJob.perform_later }
        expect(GoodJob::Job.last).to have_attributes(finished_at: be_present, locked_by_id: nil, locked_at: nil)
      ensure
        GoodJob.configuration.options.delete(:lock_strategy)
      end

      it "falls back to advisory lock behavior for #{strategy} strategy via enqueue_all" do
        GoodJob.configuration.options[:lock_strategy] = strategy
        Rails.application.executor.wrap { SuccessJob.queue_adapter.enqueue_all([SuccessJob.new]) }
        expect(GoodJob::Job.last).to have_attributes(finished_at: be_present, locked_by_id: nil, locked_at: nil)
      ensure
        GoodJob.configuration.options.delete(:lock_strategy)
      end
    end
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
