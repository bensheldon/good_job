module GoodJob
  class DashboardsController < GoodJob::BaseController
    class JobFilter
      attr_accessor :params

      def initialize(params)
        @params = params
      end

      def last
        @_last ||= jobs.last
      end

      def jobs
        after_scheduled_at = params[:after_scheduled_at].present? ? Time.zone.parse(params[:after_scheduled_at]) : nil
        sql = GoodJob::Job.display_all(after_scheduled_at: after_scheduled_at, after_id: params[:after_id])
                          .limit(params.fetch(:limit, 10))
        sql = sql.with_job_class(params[:job_class]) if params[:job_class]
        if params[:state]
          case params[:state]
          when 'finished'
            sql = sql.finished
          when 'unfinished'
            sql = sql.unfinished
          when 'errors'
            sql = sql.where.not(error: nil)
          end
        end
        sql
      end

      def states
        {
          'finished' => GoodJob::Job.finished.count,
          'unfinished' => GoodJob::Job.unfinished.count,
          'errors' => GoodJob::Job.where.not(error: nil).count,
        }
      end

      def job_classes
        GoodJob::Job.group("serialized_params->>'job_class'").count
      end

      def to_params(override)
        {
          state: params[:state],
          job_class: params[:job_class],
        }.merge(override).delete_if { |_, v| v.nil? }
      end
    end

    def index
      @filter = JobFilter.new(params)

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
        labels << timestamp.in_time_zone.to_s
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
