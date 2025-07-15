# frozen_string_literal: true

module GoodJob
  class BaseFilter
    DEFAULT_LIMIT = 25
    EMPTY = '[none]'

    attr_accessor :params, :base_query

    def initialize(params, base_query = nil)
      @params = params
      @base_query = base_query || default_base_query
    end

    def records
      after_at = params[:after_at].present? ? Time.zone.parse(params[:after_at]) : nil
      after_id = params[:after_id] if after_at
      limit = params.fetch(:limit, DEFAULT_LIMIT)

      query_for_records.display_all(
        ordered_by: ordered_by,
        after_at: after_at,
        after_id: after_id
      ).limit(limit)
    end

    def last
      @_last ||= records.last
    end

    def queues
      base_query.group(:queue_name).count
                .sort_by { |name, _count| name.presence || EMPTY }
                .to_h
    end

    def job_classes
      filtered_query(params.slice(:queue_name)).unscope(:select)
                                               .group(GoodJob::Job.params_job_class).count
                                               .sort_by { |name, _count| name.to_s }
                                               .to_h
    end

    def states
      raise NotImplementedError
    end

    def state_names
      raise NotImplementedError
    end

    def to_params(override = {})
      {
        job_class: params[:job_class],
        limit: params[:limit],
        queue_name: params[:queue_name],
        query: params[:query],
        state: params[:state],
        cron_key: params[:cron_key],
        finished_since: params[:finished_since],
      }.merge(override).delete_if { |_, v| v.blank? }
    end

    def filtered_query(filtered_params = params)
      raise NotImplementedError
    end

    def filtered_count
      filtered_query.count
    end

    def ordered_by
      %w[created_at desc]
    end

    def next_page_params
      order_column = ordered_by.first

      {
        after_at: records.last&.send(order_column),
        after_id: records.last&.id,
      }.merge(to_params)
    end

    private

    def query_for_records
      raise NotImplementedError
    end

    def default_base_query
      raise NotImplementedError
    end
  end
end
