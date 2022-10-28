# frozen_string_literal: true
module GoodJob
  module ActiveJobExtensions
    module Logging
      extend ActiveSupport::Concern

      included do
        around_perform do |job, block|
          original_logger = job.logger
          job.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(LogDevice.new(job)).extend(ActiveSupport::Logger.broadcast(original_logger)))
          block.call
        ensure
          job.logger = original_logger
        end
      end

      class LogDevice
        cattr_accessor :logs, default: Concurrent::Array.new

        def initialize(job)
          @job = job
        end

        def write(message)
          self.class.logs << [@job.provider_job_id, message.strip]
        end

        def close
          nil
        end

        def reopen(_log = nil)
          nil
        end
      end
    end
  end
end
