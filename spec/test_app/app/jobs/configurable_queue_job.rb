class ConfigurableQueueJob < ApplicationJob
  queue_as do
    kword_args = self.arguments.first
    kword_args.fetch(:queue_as)
  end

  def perform
  end
end