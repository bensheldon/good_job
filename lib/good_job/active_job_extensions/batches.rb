# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Batches
      extend ActiveSupport::Concern

      def batch
        @_batch ||= CurrentThread.execution&.batch&.to_batch
      end
      alias batch? batch
    end
  end
end
