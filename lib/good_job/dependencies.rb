# frozen_string_literal: true

module GoodJob # :nodoc:
  # Extends GoodJob module to track Rails boot dependencies.
  module Dependencies
    extend ActiveSupport::Concern

    included do
      mattr_accessor :_framework_ready, default: false
    end

    class_methods do
      # Whether Rails framework has sufficiently initialized to enable Async execution.
      def async_ready?
        Rails.application.initialized? || _framework_ready
      end

      def _start_async_adapters
        return unless async_ready?

        ActiveJob::Base.queue_adapter # Ensure Active Job is initialized
        GoodJob::Adapter.instances
                        .select(&:execute_async?)
                        .reject(&:async_started?)
                        .each(&:start_async)
      end
    end
  end
end
