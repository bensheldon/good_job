# frozen_string_literal: true
module GoodJob
  class ExecutionsFilter < BaseFilter
    def states
      {
        'finished' => base_query.finished.count,
        'unfinished' => base_query.unfinished.count,
        'running' => base_query.running.count,
        'errors' => base_query.where.not(error: nil).count,
      }
    end

    private

    def default_base_query
      GoodJob::Execution.all
    end

    def filtered_query
      query = base_query
      query = query.job_class(params[:job_class]) if params[:job_class]
      query = query.where(queue_name: params[:queue_name]) if params[:queue_name]

      if params[:state]
        case params[:state]
        when 'finished'
          query = query.finished
        when 'unfinished'
          query = query.unfinished
        when 'running'
          query = query.running
        when 'errors'
          query = query.where.not(error: nil)
        end
      end

      query
    end
  end
end
