module GoodJob
  # Ruby on Rails integration.
  class Railtie < ::Rails::Railtie
    initializer "good_job.logger" do
      ActiveSupport.on_load(:good_job) { self.logger = ::Rails.logger }
      GoodJob::LogSubscriber.attach_to :good_job
    end

    initializer "good_job.active_job_notifications" do
      ActiveSupport::Notifications.subscribe "enqueue_retry.active_job" do |event|
        GoodJob::CurrentExecution.error_on_retry = event.payload[:error]
      end

      ActiveSupport::Notifications.subscribe "discard.active_job" do |event|
        GoodJob::CurrentExecution.error_on_discard = event.payload[:error]
      end
    end
  end
end
