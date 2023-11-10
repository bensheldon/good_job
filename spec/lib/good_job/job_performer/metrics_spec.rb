# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::JobPerformer::Metrics do
  describe '#to_h' do
    it 'contains the expected keys' do
      metrics = described_class.new

      expect(metrics.to_h).to eq(
        {
          empty_executions_count: 0,
          errored_executions_count: 0,
          succeeded_executions_count: 0,
          total_executions_count: 0,
          execution_at: nil,
          check_queue_at: nil,
        }
      )
    end
  end
end
