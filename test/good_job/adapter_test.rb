require 'test_helper'

class GoodJob::Adapter::Test < ActiveSupport::TestCase
  class ExampleJob < ApplicationJob
    self.queue_name = 'test'
    self.priority = 50

    def perform(*args, **kwargs)
      thread_name = Thread.current.name || Thread.current.object_id

      THREAD_JOBS[thread_name] ||= []
      THREAD_JOBS[thread_name] << provider_job_id

      RUN_JOBS << { args: args, kwargs: kwargs }
    end
  end

  setup do
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_adapter
  end

  test "enqueuing adds to GoodJobs table" do
    ExampleJob.perform_later('first', 'second', keyword_arg: 'keyword_arg')
    assert_equal 1, GoodJob::Job.count
  end
end
