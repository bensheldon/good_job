module GoodJob
  class DashboardsController < GoodJob::BaseController
    def index
      @jobs = GoodJob::Job.display_all(after_scheduled_at: params[:after_scheduled_at], after_id: params[:after_id])
                          .limit(params.fetch(:limit, 10))

      job_data = GoodJob::Job.connection.exec_query Arel.sql(<<~SQL.squish)
        SELECT *
        FROM generate_series(
          date_trunc('hour', NOW() - '1 day'::interval),
          date_trunc('hour', NOW()),
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
        ORDER BY timestamp DESC
      SQL

      queue_names = job_data.map { |d| d['queue_name'] }.uniq
      labels = []
      queues_data = job_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp
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
