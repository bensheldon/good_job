# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Batches do
  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)

    stub_const 'RESULTS', Concurrent::Array.new
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Batches

      def perform
        RESULTS << batch.properties[:some_property] if batch
      end
    end)
  end

  describe 'batch accessors' do
    it 'access batch' do
      batch = Rails.application.executor.wrap do
        GoodJob::Batch.enqueue(some_property: "Apple") do
          TestJob.perform_later
          TestJob.perform_later
        end
      end

      expect(batch).to be_a GoodJob::Batch
      expect(batch).to be_finished

      expect(RESULTS).to eq %w[Apple Apple]
    end

    it "does not leak batch into perform_now" do
      stub_const("WrapperJob", Class.new(ActiveJob::Base) do
        include GoodJob::ActiveJobExtensions::Batches

        def perform
          TestJob.perform_now
        end
      end)

      batch = Rails.application.executor.wrap do
        GoodJob::Batch.enqueue(some_property: "Apple") do
          WrapperJob.perform_later
        end
      end

      expect(batch).to be_finished
      expect(RESULTS).to eq []
    end
  end

  describe "enequeue" do
    context 'when job does not have GoodJob Adapter' do
      before do
        allow(GoodJob.logger).to receive(:debug).and_call_original

        stub_const("TestJob", Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Batches

          self.queue_adapter = :inline

          def perform
            nil
          end
        end)
      end

      it 'warns when enqueued in a bulk capture block' do
        GoodJob::Bulk.capture { TestJob.perform_later }
        expect(GoodJob.logger).to have_received(:debug).with(/TestJob was enqueued within a batch or bulk capture block but is not using the GoodJob Adapter; the job will not appear in GoodJob./)
      end

      it 'warns when enqueued in a batch capture block' do
        GoodJob::Batch.enqueue { TestJob.perform_later }
        expect(GoodJob.logger).to have_received(:debug).with(/TestJob was enqueued within a batch or bulk capture block but is not using the GoodJob Adapter; the job will not appear in GoodJob./)
      end

      it 'warns when directly added to a batch' do
        GoodJob::Batch.enqueue(TestJob.new)
        expect(GoodJob.logger).to have_received(:debug).with(/TestJob was enqueued within a batch or bulk capture block but is not using the GoodJob Adapter; the job will not appear in GoodJob./)
      end
    end
  end
end
