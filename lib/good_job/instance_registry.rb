# frozen_string_literal: true

require "concurrent/array"

module GoodJob # :nodoc:
  # Tracks instances of a class in a class-level +instances+ registry so they can be
  # shut down or restarted together (e.g. by {GoodJob.shutdown} and {GoodJob.restart}).
  # Instances remain in the registry after they are shut down so that they can be
  # restarted; use +prune+ to remove them so they can be garbage collected.
  module InstanceRegistry
    extend ActiveSupport::Concern

    included do
      # @!attribute [r] instances
      #   @!scope class
      #   List of all registered instances in the current process.
      #   @return [Array]
      cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false
    end

    class_methods do
      # Removes prunable (e.g. shut down) instances from the registry so they can be garbage collected.
      # Instances are re-registered if they are started again.
      # @param candidates [Array] Instances to prune; defaults to all registered instances.
      # @return [Array] The pruned instances.
      def prune(*candidates)
        candidates = instances if candidates.empty?
        pruned = candidates.select { |instance| instances.include?(instance) && instance.prunable? }
        instances.delete_if { |instance| pruned.include?(instance) }
        pruned
      end
    end

    # Whether the instance can be removed from the registry.
    # @return [Boolean]
    def prunable?
      shutdown?
    end

    private

    def register_instance
      instances = self.class.instances
      instances << self unless instances.include?(self)
    end
  end
end
