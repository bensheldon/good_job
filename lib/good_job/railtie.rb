module GoodJob
  # Ruby on Rails integration.
  class Railtie < ::Rails::Railtie
    config.good_job = ActiveSupport::OrderedOptions.new

    initializer "good_job.logger" do |_app|
      ActiveSupport.on_load(:good_job) do
        self.logger = ::Rails.logger
      end
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

    config.after_initialize do
      GoodJob::Scheduler.instances.each(&:warm_cache)
    end
  end
end
