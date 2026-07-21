# frozen_string_literal: true

module GoodJob
  class BatchesFilter < BaseFilter
    def job_count(batch)
      job_counts.fetch(batch.id, 0)
    end

    def filtered_query(_filtered_params = params)
      base_query
    end

    def query_for_records
      base_query
    end

    def default_base_query
      GoodJob::BatchRecord.all
    end

    private

    def job_counts
      @_job_counts ||= GoodJob::Job.where(batch_id: records.map(&:id)).group(:batch_id).count
    end
  end
end
