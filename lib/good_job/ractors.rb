# frozen_string_literal: true

module GoodJob
  # Compatibility layer for running GoodJob in a Ractor-ized Rails application.
  #
  # Delegates to +ActiveSupport::Ractors+ when the Rails version provides it,
  # and otherwise falls back to behavior identical to a single-Ractor process.
  # All Ractor-related calls in GoodJob should go through this module so that
  # older Rails versions are unaffected and changes to Rails' (internal)
  # Ractor API are contained in one place.
  module Ractors
    NATIVE = begin
      require "active_support/ractors"
      ActiveSupport::Ractors.respond_to?(:on_main) && ActiveSupport::Ractors.respond_to?(:store_if_absent)
    rescue LoadError
      false
    end

    # Prepended to the Rails application's singleton class so that +Rails.application.ractorize!+
    # also makes GoodJob's global state shareable.
    module ApplicationExtension
      def ractorize!
        GoodJob.ractorize!
        super
      end
    end

    LOCAL_STORAGE = Concurrent::Map.new
    private_constant :LOCAL_STORAGE

    class << self
      # Whether the current Rails version supports Ractors.
      # @return [Boolean]
      def enabled?
        NATIVE
      end

      # Whether the current Ractor is the main Ractor.
      # @return [Boolean]
      def main?
        NATIVE ? ActiveSupport::Ractors.main? : true
      end

      # Deep-freezes +obj+ so it can be shared across Ractors.
      # @return [Object]
      def make_shareable(obj)
        NATIVE ? ActiveSupport::Ractors.make_shareable(obj) : obj
      end

      # Attempts to make +obj+, which may contain user-provided procs,
      # shareable. If it cannot be made shareable, the application's
      # +ActiveSupport::Ractors.unshareable_proc_action+ decides whether to
      # raise, warn, or return it unchanged.
      # @return [Object]
      def try_make_shareable(obj)
        return obj unless NATIVE

        ActiveSupport::Ractors.make_shareable(obj)
      rescue Ractor::IsolationError
        raise unless ActiveSupport::Ractors.unshareable_proc_action

        ActiveSupport::Ractors.try_make_shareable(obj)
      end

      # Attempts to make a user-provided proc shareable, according to the
      # application's +ActiveSupport::Ractors.unshareable_proc_action+.
      # @return [Proc, nil]
      def try_shareable_proc(proc)
        return proc unless NATIVE && proc.is_a?(Proc)

        ActiveSupport::Ractors.try_shareable_proc(proc)
      end

      # Runs the block on the main Ractor and returns its (shareable) result.
      # When already on the main Ractor, or Ractors are unsupported, the block
      # is called directly.
      def on_main(obj = nil, &block)
        if NATIVE
          ActiveSupport::Ractors.on_main(obj, &block)
        else
          obj.instance_eval(&block)
        end
      end

      # Returns the value stored under +key+ for the current Ractor,
      # initializing it with the block on first access. Without Ractor
      # support, the value is process-wide.
      def local(key, &block)
        if NATIVE
          ActiveSupport::Ractors.store_if_absent(key, &block)
        else
          LOCAL_STORAGE.compute_if_absent(key, &block)
        end
      end
    end
  end
end
