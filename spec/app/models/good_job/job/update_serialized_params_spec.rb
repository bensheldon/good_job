# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Job, '#update_serialized_params' do
  let(:lock_id) { SecureRandom.uuid }
  let(:job) do
    TestJob.perform_later("an argument")
    described_class.last.tap do |job|
      job.update!(performed_at: Time.current, locked_by_id: lock_id, locked_at: Time.current, executions_count: 1)
    end
  end

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform(*)
      end
    end)
  end

  def persisted_params
    described_class.find(job.id).serialized_params
  end

  it 'merges the keys into the serialized params' do
    original_params = persisted_params

    expect(job.update_serialized_params({ "progress" => { "cursor" => 42 } })).to be true
    expect(persisted_params).to eq original_params.merge("progress" => { "cursor" => 42 })
  end

  it 'updates the record without marking the serialized params as changed' do
    job.update_serialized_params({ "progress" => { "cursor" => 42 } })

    expect(job.serialized_params["progress"]).to eq({ "cursor" => 42 })
    expect(job).not_to be_serialized_params_changed
  end

  it 'does not overwrite other serialized params changed since the job was loaded' do
    described_class.where(id: job.id).update_all(["serialized_params = serialized_params || ?::jsonb", { "good_job_labels" => ["changed"] }.to_json]) # rubocop:disable Rails/SkipsModelValidations

    job.update_serialized_params({ "progress" => { "cursor" => 42 } })

    expect(persisted_params).to include("good_job_labels" => ["changed"], "progress" => { "cursor" => 42 })
  end

  it 'does not update the job once another execution has taken it over' do
    described_class.where(id: job.id).update_all(executions_count: 2) # rubocop:disable Rails/SkipsModelValidations

    expect(job.update_serialized_params({ "progress" => { "cursor" => 42 } })).to be false
    expect(persisted_params).not_to have_key("progress")
    expect(job.serialized_params).not_to have_key("progress")
  end

  it 'does not update the job once it has finished' do
    described_class.where(id: job.id).update_all(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    expect(job.update_serialized_params({ "progress" => { "cursor" => 42 } })).to be false
    expect(persisted_params).not_to have_key("progress")
  end

  it 'updates the job while the execution owns it even if its process lock was released' do
    described_class.release_process(lock_id)

    expect(job.update_serialized_params({ "progress" => { "cursor" => 42 } })).to be true
  end
end
