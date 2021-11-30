# frozen_string_literal: true
module GoodJob
  # Ruby on Rails integration.
  class Railtie < ::Rails::Railtie
    config.good_job = ActiveSupport::OrderedOptions.new
    config.good_job.cron = {}

    initializer "good_job.logger" do |_app|
      ActiveSupport.on_load(:good_job) do
        self.logger = ::Rails.logger if GoodJob.logger == GoodJob::DEFAULT_LOGGER
      end
      GoodJob::LogSubscriber.attach_to :good_job
    end

    initializer "good_job.active_job_notifications" do
      ActiveSupport::Notifications.subscribe "enqueue_retry.active_job" do |event|
        GoodJob::CurrentThread.error_on_retry = event.payload[:error]
      end

      ActiveSupport::Notifications.subscribe "discard.active_job" do |event|
        GoodJob::CurrentThread.error_on_discard = event.payload[:error]
      end
    end

    initializer 'good_job.rails_config' do
      config.after_initialize do
        rails_config = Rails.application.config.good_job

        GoodJob.logger = rails_config[:logger] if rails_config.key?(:logger)
        GoodJob.on_thread_error = rails_config[:on_thread_error] if rails_config.key?(:on_thread_error)
        GoodJob.preserve_job_records = rails_config[:preserve_job_records] if rails_config.key?(:preserve_job_records)
        GoodJob.retry_on_unhandled_error = rails_config[:retry_on_unhandled_error] if rails_config.key?(:retry_on_unhandled_error)
      end
    end

    initializer "good_job.start_async" do
      config.after_initialize do
        GoodJob::Adapter.instances.each(&:start_async)
      end
    end
  end
end
