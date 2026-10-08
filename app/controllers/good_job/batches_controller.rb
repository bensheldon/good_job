# frozen_string_literal: true

module GoodJob
  class BatchesController < GoodJob::ApplicationController
    def index
      @filter = BatchesFilter.new(params)
    end

    def show
      batches = GoodJob::BatchRecord.all
      batches = batches.preload(jobs: :concurrency_claims, callback_jobs: :concurrency_claims) if GoodJob::ConcurrencyClaim.table_exists?
      @batch = batches.find(params[:id])
    end

    def retry
      @batch = GoodJob::Batch.find(params[:id])
      @batch.retry
      redirect_back(fallback_location: batches_path, notice: t(".notice"), status: :see_other)
    end
  end
end
