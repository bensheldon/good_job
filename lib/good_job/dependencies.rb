# frozen_string_literal: true

module GoodJob # :nodoc:
  # Extends GoodJob module to track Rails boot dependencies.
  module Dependencies
    extend ActiveSupport::Concern

    included do
      # @!attribute [rw] _rails_after_initialize_hook_called
      #   @!scope class
      #   Whether Railtie.after_initialize has been called yet (default: +false+).
      #   This will be set on  but before +Rails.application.initialize?+ is +true+.
      #   @return [Boolean]
      mattr_accessor :_rails_after_initialize_hook_called, default: false

      # @!attribute [rw] _active_job_loaded
      #   @!scope class
      #   Whether ActiveJob has loaded (default: +false+).
      #   @return [Boolean]
      mattr_accessor :_active_job_loaded, default: false

      # @!attribute [rw] _active_record_loaded
      #   @!scope class
      #   Whether ActiveRecord has loaded (default: +false+).
      #   @return [Boolean]
      mattr_accessor :_active_record_loaded, default: false
    end

    class_methods do
      # Whether GoodJob's  has been initialized as of the calling of +Railtie.after_initialize+.
      # @return [Boolean]
      def async_ready?
        Rails.application.initialized? || (
           _rails_after_initialize_hook_called &&
           _active_job_loaded &&
           _active_record_loaded
         )
      end

      def start_async_adapters
        return unless async_ready?

        GoodJob::Adapter.instances
                        .select(&:execute_async?)
                        .reject(&:async_started?)
                        .each(&:start_async)
      end
    end
  end
end
