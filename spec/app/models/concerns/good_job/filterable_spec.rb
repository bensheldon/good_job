# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Filterable do
  let(:model_class) { GoodJob::Job }
  let!(:job) do
    model_class.create(
      active_job_id: SecureRandom.uuid,
      queue_name: "default",
      serialized_params: { example_key: 'example_value' },
      labels: %w[buffalo gopher],
      error: "ExampleJob::ExampleError: a message"
    )
  end

  describe '.search_test' do
    it 'searches serialized params' do
      expect(model_class.search_text('example_value')).to include(job)
    end

    it 'searches record id' do
      expect(model_class.search_text(job.id)).to include(job)
    end

    it 'searches active_job_id' do
      expect(model_class.search_text(job.active_job_id)).to include(job)
    end

    it 'searches labels' do
      expect(model_class.search_text('buffalo')).to include(job)
      expect(model_class.search_text('gopher')).to include(job)
      expect(model_class.search_text('hippo')).not_to include(job)
    end

    it 'searches errors' do
      expect(model_class.search_text('ExampleError')).to include(job)
    end

    it 'searches strings with colons' do
      expect(model_class.search_text('ExampleJob::ExampleError')).to include(job)
    end

    it 'filters out non-matching records' do
      expect(model_class.search_text('ghost')).to be_empty
    end

    it 'is chainable and reversible' do
      expect(model_class.where.not(id: nil).search_text('example_value').reverse).to include(job)
    end
  end
end
