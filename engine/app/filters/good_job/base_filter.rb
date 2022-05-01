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
      after_scheduled_at = params[:after_scheduled_at].present? ? Time.zone.parse(params[:after_scheduled_at]) : nil

      filtered_query.display_all(
        after_scheduled_at: after_scheduled_at,
        after_id: params[:after_id]
      ).limit(params.fetch(:limit, DEFAULT_LIMIT))
    end

    def last
      @_last ||= records.last
    end

    def job_classes
      base_query.group("serialized_params->>'job_class'").count
                .sort_by { |name, _count| name.to_s }
                .to_h
    end

    def queues
      base_query.group(:queue_name).count
                .sort_by { |name, _count| name.to_s || EMPTY }
                .to_h
    end

    def states
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
      }.merge(override).delete_if { |_, v| v.blank? }
    end

    def filtered_query
      raise NotImplementedError
    end

    def filtered_count
      filtered_query.count
    end

    private

    def default_base_query
      raise NotImplementedError
    end
  end
end
