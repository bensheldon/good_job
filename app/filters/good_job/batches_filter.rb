# frozen_string_literal: true

module GoodJob
  class BatchesFilter < BaseFilter
    def filtered_query(_filtered_params = params)
      base_query
    end

    def query_for_records
      default_base_query
    end

    def default_base_query
      GoodJob::BatchRecord.includes(:jobs)
    end
  end
end
