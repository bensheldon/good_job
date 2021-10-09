# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::JobsFilter do
  subject(:filter) { described_class.new(params) }

  let(:params) { {} }

  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)

    ExampleJob.set(queue: 'default').perform_later('success')
    ExampleJob.set(queue: 'mice').perform_later('error_once')
    begin
      ExampleJob.set(queue: 'elephants').perform_later('dead')
    rescue ExampleJob::DeadError
      nil
    end

    running_job = ExampleJob.perform_later('success')
    running_execution = GoodJob::Execution.find(running_job.provider_job_id)
    running_execution.update!(
      finished_at: nil
    )
    running_execution.advisory_lock
  end

  after do
    GoodJob::Execution.advisory_unlock_session
  end

  describe '#job_classes' do
    it 'is a valid result' do
      expect(filter.job_classes).to eq({
                                         'ExampleJob' => 4,
                                       })
    end
  end

  describe '#queues' do
    it 'is a valid result' do
      expect(filter.queues).to eq({
                                    "default" => 2,
                                    "elephants" => 1,
                                    "mice" => 1,
                                  })
    end
  end

  describe '#states' do
    it 'is a valid result' do
      expect(filter.states).to eq({
                                    "scheduled" => 0,
                                    "retried" => 0,
                                    "queued" => 0,
                                    "running" => 1,
                                    "finished" => 2,
                                    "discarded" => 1,
                                  })
    end
  end

  describe '#chart_data' do
    it 'is a valid result' do
      expect(filter.chart_data).to be_a Hash
    end
  end

  describe '#records' do
    it 'is a valid result' do
      expect(filter.records.size).to eq 4
    end

    context 'when filtered by state' do
      before do
        params[:state] = 'running'
      end

      it 'returns a limited set of results' do
        expect(filter.records.size).to eq 1
      end
    end
  end

  %w[
    scheduled
    retried
    queued
    running
    finished
    discarded
  ].each do |filter_state|
    context "with filter state '#{filter_state}'" do
      before do
        params[:state] = filter_state
      end

      it 'returns working results' do
        expect(filter.job_classes).to be_a Hash
        expect(filter.queues).to be_a Hash
        expect(filter.states).to be_a Hash
        expect(filter.chart_data).to be_a Hash

        expect(filter.records.to_a).to be_an Array
      end
    end
  end
end
