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
end
