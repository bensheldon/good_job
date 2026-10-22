# frozen_string_literal: true

module GoodJob
  # Hides sensitive Active Job arguments when displaying Job/Execution records in the Dashboard.
  module FilteredArguments
    # Active Job arguments with sensitive values replaced by +[FILTERED]+.
    # Every argument is filtered when the job class has +log_arguments+ disabled
    # (e.g. +config.active_job.log_arguments = false+); otherwise hash values whose
    # keys match +Rails.application.config.filter_parameters+ are filtered.
    # @return [Array]
    def display_arguments
      arguments = serialized_params.fetch("arguments", [])
      return arguments.map { ActiveSupport::ParameterFilter::FILTERED } unless log_arguments?

      parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      parameter_filter.filter("arguments" => arguments)["arguments"]
    end

    private

    def log_arguments?
      active_job_class = job_class&.safe_constantize
      active_job_class = ActiveJob::Base unless active_job_class.respond_to?(:log_arguments?)
      active_job_class.log_arguments?
    end
  end
end
