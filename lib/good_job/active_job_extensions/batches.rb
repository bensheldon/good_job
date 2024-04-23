# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Batches
      extend ActiveSupport::Concern

      def batch
        @_batch ||= CurrentThread.execution&.batch&.to_batch if CurrentThread.execution.present? && CurrentThread.execution.active_job_id == job_id
      end
      alias batch? batch
    end
  end
end
