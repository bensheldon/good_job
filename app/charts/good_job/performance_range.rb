# frozen_string_literal: true

module GoodJob
  class PerformanceRange
    PARAMETER_KEYS = %w[chart_range chart_start chart_end].freeze
    TIME_ZONE_PARAMETER_KEY = "chart_time_zone"
    INPUT_PARAMETER_KEYS = [*PARAMETER_KEYS, TIME_ZONE_PARAMETER_KEY].freeze
    DEFAULT_KEY = "24h"
    MAXIMUM = 24.hours * 31
    MAXIMUM_TIME_ZONE_LENGTH = 255
    # Restrict custom bounds to portable four-digit years in the timezone used by the page.
    MINIMUM_YEAR = 1000
    MAXIMUM_YEAR = 9999
    MINIMUM_LOCAL_VALUE = "1000-01-01T00:00:00"
    MAXIMUM_LOCAL_VALUE = "9999-12-31T23:59:59"
    TIMESTAMP_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/
    LOCAL_TIMESTAMP_PATTERN = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?\z/

    OPTIONS = {
      "1h" => {
        label: "1h",
        duration: 1.hour,
        interval_seconds: 5.minutes.to_i,
        label_format: "%H:%M",
        label_style: "time",
      },
      "6h" => {
        label: "6h",
        duration: 6.hours,
        interval_seconds: 15.minutes.to_i,
        label_format: "%H:%M",
        label_style: "time",
      },
      "24h" => {
        label: "24h",
        duration: 24.hours,
        interval_seconds: 1.hour.to_i,
        label_format: "%H:%M",
        label_style: "time",
      },
      "7d" => {
        label: "7d",
        duration: 24.hours * 7,
        interval_seconds: 6.hours.to_i,
        label_format: "%b %-d %H:%M",
        label_style: "date_time",
      },
    }.freeze

    CUSTOM_INTERVALS = [
      [2.hours, OPTIONS.fetch("1h")],
      [12.hours, OPTIONS.fetch("6h")],
      [48.hours, OPTIONS.fetch("24h")],
      [MAXIMUM, OPTIONS.fetch("7d")],
    ].freeze

    attr_reader :end_time, :interval_seconds, :key, :label_format, :label_style, :start_time

    def initialize(params = nil, query_string: nil, **parameter_keywords)
      @params = params || parameter_keywords
      @repeated_parameter_keys = repeated_parameter_keys(query_string)
      @local_time_zone = local_time_zone
      resolve
    end

    def apply(relation)
      relation.where(scheduled_at: start_time...end_time)
    end

    def canonical_parameters?(query_parameters)
      query_parameters.slice(*INPUT_PARAMETER_KEYS) == to_params
    end

    def chart_timestamp_label(timestamp)
      timestamp.in_time_zone.strftime(label_format)
    end

    def canonical_timestamp(timestamp)
      timestamp = timestamp.in_time_zone
      # ISO 8601 cannot preserve the sub-minute historical offsets present in some IANA zones.
      timestamp.utc_offset.remainder(60).zero? ? timestamp.iso8601 : timestamp.utc.iso8601
    end

    def custom?
      key.nil?
    end

    def default?
      to_params.empty?
    end

    def end_label
      range_label(end_time)
    end

    def end_local_value
      local_value(end_time)
    end

    def navigation_params
      return to_params unless key

      # A preset is a relative definition; navigation also carries this evaluated instance.
      {
        "chart_range" => key,
        "chart_start" => canonical_timestamp(start_time),
        "chart_end" => canonical_timestamp(end_time),
      }
    end

    def options
      OPTIONS.map { |option_key, option| { key: option_key, label: option.fetch(:label) } }
    end

    def start_end_binds
      [
        query_attribute("start_time", start_time, ActiveRecord::Type::DateTime.new),
        query_attribute("end_time", end_time, ActiveRecord::Type::DateTime.new),
      ]
    end

    def start_label
      range_label(start_time)
    end

    def start_local_value
      local_value(start_time)
    end

    # Keep this order in sync with the $1/$2/$3 placeholders in PerformanceIndexChart.
    def time_series_binds
      [
        query_attribute("series_start_time", series_start_time, ActiveRecord::Type::DateTime.new),
        query_attribute("series_end_time", series_end_time, ActiveRecord::Type::DateTime.new),
        query_attribute("interval_seconds", interval_seconds, ActiveRecord::Type::Integer.new),
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

    def to_params
      @canonical_params.dup
    end

    private

    def align_time(time)
      Time.at((time.to_f / interval_seconds).floor * interval_seconds).utc
    end

    def custom_times
      parsed_start = parse_time("chart_start", @params[:chart_start])
      parsed_end = parse_time("chart_end", @params[:chart_end])
      return unless parsed_start && parsed_end && parsed_start < parsed_end

      parsed_start = parsed_end - MAXIMUM if parsed_end - parsed_start > MAXIMUM
      [parsed_start, parsed_end]
    end

    def parse_time(parameter_key, value)
      return if @repeated_parameter_keys.include?(parameter_key)
      return unless value.is_a?(String)

      timestamp = if TIMESTAMP_PATTERN.match?(value)
                    Time.iso8601(value)
                  elsif (local_match = LOCAL_TIMESTAMP_PATTERN.match(value))
                    parse_local_time(parameter_key, local_match)
                  end
      return unless timestamp
      return unless timestamp.to_f.finite?

      timestamp = timestamp.in_time_zone.change(usec: 0)
      return unless timestamp.year.between?(MINIMUM_YEAR, MAXIMUM_YEAR)

      timestamp
    rescue ArgumentError, RangeError
      nil
    end

    def repeated_parameter_keys(query_string)
      return [] if query_string.blank?

      keys = URI.decode_www_form(query_string).filter_map do |key, _value|
        key if INPUT_PARAMETER_KEYS.include?(key)
      end
      keys.tally.select { |_key, count| count > 1 }.keys
    rescue ArgumentError
      INPUT_PARAMETER_KEYS
    end

    def query_attribute(name, value, type)
      ActiveRecord::Relation::QueryAttribute.new(name, value, type)
    end

    def local_value(time)
      time.in_time_zone.strftime("%Y-%m-%dT%H:%M:%S")
    end

    def parse_local_time(parameter_key, match)
      return unless @local_time_zone

      components = match.captures
      components[-1] ||= "0"
      numeric_components = components.map { |component| Integer(component, 10) }
      local_time = Time.utc(*numeric_components)
      normalized_value = format("%04d-%02d-%02dT%02d:%02d:%02d", *numeric_components)
      return unless local_time.strftime("%Y-%m-%dT%H:%M:%S") == normalized_value

      periods = @local_time_zone.tzinfo.periods_for_local(local_time)
      return if periods.empty?

      # A local input cannot carry an offset. Include both repeated fall-back occurrences
      # by resolving starts to the earlier instant and ends to the later instant.
      instants = periods.map do |period|
        (local_time - period.utc_total_offset).in_time_zone
      end
      parameter_key == "chart_end" ? instants.max : instants.min
    end

    def local_time_zone
      return if @repeated_parameter_keys.include?(TIME_ZONE_PARAMETER_KEY)

      value = @params[TIME_ZONE_PARAMETER_KEY] || @params[TIME_ZONE_PARAMETER_KEY.to_sym]
      return Time.zone if value.nil?
      return unless value.is_a?(String) && value.bytesize <= MAXIMUM_TIME_ZONE_LENGTH
      return unless /\A[A-Za-z0-9._+-]+(?:\/[A-Za-z0-9._+-]+)*\z/.match?(value)

      tzinfo = TZInfo::Timezone.get(value)
      ActiveSupport::TimeZone.create(value, nil, tzinfo)
    rescue TZInfo::InvalidTimezoneIdentifier
      nil
    end

    def range_label(time)
      time.in_time_zone.strftime("%b %-d, %H:%M:%S")
    end

    def resolve
      range_key = preset_key

      if (times = custom_times)
        @start_time, @end_time = times

        # Do not attach a preset identity to tampered bounds with a different elapsed duration.
        if range_key && end_time - start_time == OPTIONS.fetch(range_key).fetch(:duration)
          @key = range_key
          @canonical_params = navigation_params
          options = OPTIONS.fetch(key)
        else
          @key = nil
          @canonical_params = {
            "chart_start" => canonical_timestamp(start_time),
            "chart_end" => canonical_timestamp(end_time),
          }
          options = CUSTOM_INTERVALS.find { |duration, _options| end_time - start_time <= duration }&.last
          options ||= CUSTOM_INTERVALS.last.last
        end
      elsif range_key
        @key = range_key
        options = OPTIONS.fetch(key)
        @end_time = current_end_time
        @start_time = end_time - options.fetch(:duration)
        @canonical_params = { "chart_range" => key }
      else
        @key = DEFAULT_KEY
        options = OPTIONS.fetch(key)
        @end_time = current_end_time
        @start_time = end_time - options.fetch(:duration)
        @canonical_params = {}
      end

      @interval_seconds = options.fetch(:interval_seconds)
      @label_format = options.fetch(:label_format)
      @label_style = options.fetch(:label_style)
    end

    def preset_key
      return if @repeated_parameter_keys.include?("chart_range")

      value = @params[:chart_range]
      value if value.is_a?(String) && OPTIONS.key?(value)
    end

    def series_end_time
      align_time(end_time - 0.000001)
    end

    def series_start_time
      align_time(start_time)
    end

    def current_end_time
      current_time = Time.current
      current_time.usec.zero? ? current_time : current_time.ceil
    end
  end
end
