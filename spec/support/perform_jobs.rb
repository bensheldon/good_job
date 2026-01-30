# frozen_string_literal: true

module PerformJobsHelper
  def perform_good_job_inline
    original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
    yield
  ensure
    ActiveJob::Base.queue_adapter = original_queue_adapter
  end

  def perform_good_job_external
    original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    yield
  ensure
    ActiveJob::Base.queue_adapter = original_queue_adapter
  end
end

RSpec.configure do |config|
  config.include PerformJobsHelper
end
