# frozen_string_literal: true

module GoodJob
  class BatchesFilter < BaseFilter
    def records
      after_created_at = params[:after_created_at].present? ? Time.zone.parse(params[:after_created_at]) : nil

      filtered_query.display_all(
        after_created_at: after_created_at,
        after_id: params[:after_id]
      ).limit(params.fetch(:limit, DEFAULT_LIMIT))
    end

    def filtered_query(_filtered_params = params)
      base_query
    end

    def default_base_query
      GoodJob::BatchRecord.includes(:jobs)
    end
  end
end
