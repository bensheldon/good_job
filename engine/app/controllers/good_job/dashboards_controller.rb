# frozen_string_literal: true
module GoodJob
  class DashboardsController < GoodJob::BaseController
    class ExecutionFilter
      attr_accessor :params

      def initialize(params)
        @params = params
      end

      def last
        @_last ||= executions.last
      end

      def executions
        after_scheduled_at = params[:after_scheduled_at].present? ? Time.zone.parse(params[:after_scheduled_at]) : nil
        sql = GoodJob::Execution.display_all(after_scheduled_at: after_scheduled_at, after_id: params[:after_id])
                                .limit(params.fetch(:limit, 25))
        sql = sql.job_class(params[:job_class]) if params[:job_class]
        if params[:state]
          case params[:state]
          when 'finished'
            sql = sql.finished
          when 'unfinished'
            sql = sql.unfinished
          when 'running'
            sql = sql.running
          when 'errors'
            sql = sql.where.not(error: nil)
          end
        end
        sql
      end

      def states
        {
          'finished' => GoodJob::Execution.finished.count,
          'unfinished' => GoodJob::Execution.unfinished.count,
          'running' => GoodJob::Execution.running.count,
          'errors' => GoodJob::Execution.where.not(error: nil).count,
        }
      end

      def job_classes
        GoodJob::Execution.group("serialized_params->>'job_class'").count
                          .sort_by { |name, _count| name }
      end

      def to_params(override)
        {
          state: params[:state],
          job_class: params[:job_class],
        }.merge(override).delete_if { |_, v| v.nil? }
      end
    end

    def index
      @filter = ExecutionFilter.new(params)

      count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
        SELECT *
        FROM generate_series(
          date_trunc('hour', $1::timestamp),
          date_trunc('hour', $2::timestamp),
          '1 hour'
        ) timestamp
        LEFT JOIN (
          SELECT
              date_trunc('hour', scheduled_at) AS scheduled_at,
              queue_name,
              count(*) AS count
            FROM (
              SELECT
                COALESCE(scheduled_at, created_at)::timestamp AS scheduled_at,
                queue_name
              FROM good_jobs
            ) sources
            GROUP BY date_trunc('hour', scheduled_at), queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      current_time = Time.current
      binds = [[nil, current_time - 1.day], [nil, current_time]]
      executions_data = GoodJob::Execution.connection.exec_query(count_query, "GoodJob Dashboard Chart", binds)

      queue_names = executions_data.map { |d| d['queue_name'] }.uniq
      labels = []
      queues_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp.in_time_zone.strftime('%H:%M %z')
        queue_names.each do |queue_name|
          (hash[queue_name] ||= []) << values.find { |d| d['queue_name'] == queue_name }&.[]('count')
        end
      end

      @chart = {
        labels: labels,
        series: queues_data.map do |queue, data|
          {
            name: queue,
            data: data,
          }
        end,
      }
    end
  end
end
