# frozen_string_literal: true

module GoodJob
  class BaseChart
    DEFAULT_CHART_RANGE_KEY = "24h"
    MAX_CHART_RANGE = 31.days

    CHART_RANGE_OPTIONS = {
      "1h" => {
        label: "1h",
        duration: 1.hour,
        interval_seconds: 5.minutes.to_i,
        label_format: "%H:%M",
      },
      "6h" => {
        label: "6h",
        duration: 6.hours,
        interval_seconds: 15.minutes.to_i,
        label_format: "%H:%M",
      },
      "24h" => {
        label: "24h",
        duration: 1.day,
        interval_seconds: 1.hour.to_i,
        label_format: "%H:%M",
      },
      "7d" => {
        label: "7d",
        duration: 7.days,
        interval_seconds: 6.hours.to_i,
        label_format: "%b %-d %H:%M",
      },
    }.freeze

    CUSTOM_CHART_INTERVALS = [
      [2.hours, CHART_RANGE_OPTIONS.fetch("1h")],
      [12.hours, CHART_RANGE_OPTIONS.fetch("6h")],
      [2.days, CHART_RANGE_OPTIONS.fetch("24h")],
      [MAX_CHART_RANGE, CHART_RANGE_OPTIONS.fetch("7d")],
    ].freeze

    attr_reader :params

    def initialize(params = {})
      @params = params || {}
    end

    def start_end_binds
      start_time = chart_range.fetch(:start_time)
      end_time = chart_range.fetch(:end_time)

      [
        ActiveRecord::Relation::QueryAttribute.new('start_time', start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', end_time, ActiveRecord::Type::DateTime.new),
      ]
    end

    def string_to_hsl(string)
      hash_value = string.sum

      hue = hash_value % 360
      saturation = (hash_value % 50) + 50
      lightness = '50'

      "hsl(#{hue}, #{saturation}%, #{lightness}%)"
    end

    def chart_interval_seconds
      chart_range.fetch(:interval_seconds)
    end

    def chart_range
      @_chart_range ||= custom_chart_range || preset_chart_range
    end

    def chart_metadata(timestamps)
      {
        time_series: true,
        range_key: chart_range.fetch(:key),
        start_label: chart_range_label(:start_time),
        end_label: chart_range_label(:end_time),
        custom_range: chart_range.fetch(:key).nil?,
        default_range: default_chart_range?,
        ranges: CHART_RANGE_OPTIONS.map { |key, options| { key: key, label: options.fetch(:label) } },
        interval_seconds: chart_interval_seconds,
        timestamps: timestamps,
      }
    end

    def chart_timestamp_label(timestamp)
      timestamp.in_time_zone.strftime(chart_range.fetch(:label_format))
    end

    # Keep this order in sync with the $1/$2/$3 placeholders in chart SQL.
    def time_series_binds
      [
        ActiveRecord::Relation::QueryAttribute.new('start_time', time_series_start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', time_series_end_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('interval_seconds', chart_interval_seconds, ActiveRecord::Type::Integer.new),
      ]
    end

    def time_series_bucket_sql(column_name)
      column_sql = GoodJob::Job.adapter_class.quote_column_name(column_name)

      <<~SQL.squish
        $1::timestamp +
        FLOOR(EXTRACT(EPOCH FROM (#{column_sql} - $1::timestamp)) / $3::integer) *
        $3::integer * INTERVAL '1 second'
      SQL
    end

    private

    def chart_range_label(key)
      chart_range.fetch(key).in_time_zone.strftime("%b %-d, %H:%M")
    end

    def default_chart_range?
      chart_range.fetch(:key) == DEFAULT_CHART_RANGE_KEY &&
        params[:chart_range].blank? &&
        params[:chart_start].blank? &&
        params[:chart_end].blank?
    end

    def custom_chart_range
      start_time = parse_chart_time(params[:chart_start])
      end_time = parse_chart_time(params[:chart_end])
      return unless start_time && end_time && start_time < end_time

      start_time = end_time - MAX_CHART_RANGE if end_time - start_time > MAX_CHART_RANGE

      interval_options = CUSTOM_CHART_INTERVALS.find { |duration, _options| end_time - start_time <= duration }.last
      interval_options.merge(start_time: start_time, end_time: end_time, key: nil)
    end

    def preset_chart_range
      key = params[:chart_range].presence_in(CHART_RANGE_OPTIONS.keys) || DEFAULT_CHART_RANGE_KEY
      options = CHART_RANGE_OPTIONS.fetch(key)
      end_time = Time.current

      options.merge(
        start_time: end_time - options.fetch(:duration),
        end_time: end_time,
        key: key
      )
    end

    def parse_chart_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def time_series_start_time
      align_time(chart_range.fetch(:start_time))
    end

    def time_series_end_time
      align_time(chart_range.fetch(:end_time))
    end

    def align_time(time)
      Time.at((time.to_f / chart_interval_seconds).floor * chart_interval_seconds).utc
    end
  end
end
