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
      # This hooks into the hookable places during Rails boot, which is unfortunately not Rails.application.initialized?
      # If an Adapter is initialized during boot, we want to want to start its async executors once the framework dependencies have loaded.
      # When exactly that happens is out of our control because gems or application code may touch things earlier than expected.
      # For example, as of Rails 6.1, if an ActiveRecord model is touched during boot, that triggers ActiveRecord to load,
      # which touches DestroyAssociationAsyncJob, which loads ActiveJob, which may initialize a GoodJob::Adapter, all of which
      # happens _before_ ActiveRecord finishes loading. GoodJob will deadlock if an async executor is started in the middle of
      # ActiveRecord loading.

      config.after_initialize do
        ActiveSupport.on_load(:active_record) do
          GoodJob._active_record_loaded = true
          GoodJob.start_async_adapters
        end

        ActiveSupport.on_load(:active_job) do
          GoodJob._active_job_loaded = true
          GoodJob.start_async_adapters
        end

        GoodJob._rails_after_initialize_hook_called = true
        GoodJob.start_async_adapters
      end
    end
  end
end
