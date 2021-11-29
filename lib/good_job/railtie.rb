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
        GoodJob.logger = Rails.application.config.good_job.logger unless Rails.application.config.good_job.logger.nil?
        GoodJob.on_thread_error = Rails.application.config.good_job.on_thread_error unless Rails.application.config.good_job.on_thread_error.nil?
        GoodJob.preserve_job_records = Rails.application.config.good_job.preserve_job_records unless Rails.application.config.good_job.preserve_job_records.nil?
        GoodJob.retry_on_unhandled_error = Rails.application.config.good_job.retry_on_unhandled_error unless Rails.application.config.good_job.retry_on_unhandled_error.nil?
      end
    end

    initializer "good_job.start_async" do
      config.after_initialize do
        GoodJob::Adapter.instances.each(&:start_async)
      end
    end
  end
end
