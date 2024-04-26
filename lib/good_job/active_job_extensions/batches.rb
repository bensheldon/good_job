# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Batches
      extend ActiveSupport::Concern

      included do
        before_enqueue do |job|
          GoodJob.logger.debug("#{job.class} was enqueued within a batch or bulk capture block but is not using the GoodJob Adapter; the job will not appear in GoodJob.") if (GoodJob::Bulk.current_buffer || GoodJob::Batch.current_batch_id) && !job.class.queue_adapter.is_a?(GoodJob::Adapter)
        end
      end

      def batch
        @_batch ||= CurrentThread.execution&.batch&.to_batch if CurrentThread.execution.present? && CurrentThread.execution.active_job_id == job_id
      end
      alias batch? batch
    end
  end
end
