# frozen_string_literal: true
module GoodJob
  module ActiveJobExtensions
    module Batches
      extend ActiveSupport::Concern

      def batch
        CurrentThread.execution&.batch
      end
      alias batch? batch

      def batch_callback
        CurrentThread.execution&.batch_callback
      end
      alias batch_callback? batch_callback
    end
  end
end
