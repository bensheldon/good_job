# frozen_string_literal: true

begin
  require "job-iteration"

  module JobIteration
    module Integrations
      module GoodJob
        class << self
          def call
            ::GoodJob.shutdown?
          end
        end
      end
    end
  end

  JobIteration.interruption_adapter = JobIteration::Integrations::GoodJob
rescue LoadError
  # job-iteration is not present
end
