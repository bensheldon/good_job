# frozen_string_literal: true

module GoodJob
  class BatchesController < GoodJob::ApplicationController
    def index
      @filter = BatchesFilter.new(params)
    end

    def show
      @batch = GoodJob::BatchRecord.find(params[:id])
    end

    def retry
      @batch = GoodJob::Batch.find(params[:id])
      @batch.retry
      redirect_back(fallback_location: batches_path, notice: t(".notice"), status: :see_other)
    end
  end
end
