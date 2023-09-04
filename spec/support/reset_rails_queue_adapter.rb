# frozen_string_literal: true

# https://github.com/rails/rails/issues/37270
# Avoid overriding TestQueueAdapter altogether
module ActiveJob
  module TestHelper
    # Avoid calling #descendants because JRuby has trouble with it
    # https://github.com/jruby/jruby/issues/6896
    def queue_adapter_changed_jobs
      []
    end

    module TestQueueAdapter
      module ClassMethods
        def queue_adapter # rubocop:disable Lint/UselessMethodDefinition
          super
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.around do |example|
    original_adapter = ActiveJob::Base.queue_adapter

    example.run

    ActiveJob::Base.queue_adapter = original_adapter
  end
end
