# frozen_string_literal: true
module GoodJob
  module ActiveJobExtensions
    module Logging
      extend ActiveSupport::Concern

      def self.logs
        [[GoodJob::Execution.first.id, 'Hello, world!', 'Debug level!']]
      end
    end
  end
end
