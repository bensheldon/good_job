# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::BatchesController do
  describe 'GET #show' do
    it 'styles batched job labels by their concurrency claim' do
      batch = GoodJob::BatchRecord.create!
      job_id = SecureRandom.uuid
      GoodJob::Job.create!(id: job_id, active_job_id: job_id, batch_id: batch.id, job_class: "ExampleJob", queue_name: "default", labels: %w[slow other], serialized_params: { "job_class" => "ExampleJob", "arguments" => [] })
      GoodJob::ConcurrencyClaim.create!(job_id: job_id, key: "label:slow", state: GoodJob::ConcurrencyClaim::WAITING)

      get good_job.batch_path(batch)

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("span.badge.border-warning[title='Waiting'][tabindex='0']").text).to eq "slow (Waiting)"
      expect(html.at_css("span.badge.font-monospace.text-bg-secondary").text).to eq "other"
    end
  end
end
