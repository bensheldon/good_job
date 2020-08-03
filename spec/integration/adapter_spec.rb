# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Adapter Integration' do
  let(:adapter) { GoodJob::Adapter.new }

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  before do
    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*args, **kwargs)
      end
    end)
  end

  describe '#enqueue' do
    it 'performs the job directly' do
      ExampleJob.perform_later('first', 'second', keyword_arg: 'keyword_arg')

      good_job = GoodJob::Job.last
      expect(good_job).to be_present
      expect(good_job).to have_attributes(
        queue_name: 'test',
        priority: 50
      )
    end
  end

  describe '#enqueue_at' do
    it 'assigns parameters' do
      expect do
        ExampleJob.set(wait: 1.minute).perform_later('first', 'second', keyword_arg: 'keyword_arg')
      end.to change(GoodJob::Job, :count).by(1)

      good_job = GoodJob::Job.last
      expect(good_job.queue_name).to eq 'test'
      expect(good_job.priority).to eq 50
      expect(good_job.scheduled_at).to be_within(1.second).of 1.minute.from_now
    end
  end

  describe '#provider_job_id' do
    it 'is assigned at creation' do
      enqueued_job = ExampleJob.perform_later
      good_job = GoodJob::Job.find(enqueued_job.provider_job_id)

      expect(enqueued_job.provider_job_id).to eq good_job.id
    end
  end
end
