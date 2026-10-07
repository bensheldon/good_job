# frozen_string_literal: true

module GoodJob
  module ApplicationHelper
    # Explicit helper inclusion because ApplicationController inherits from the host app.
    #
    # We can't rely on +config.action_controller.include_all_helpers = true+ in the host app.
    include IconsHelper

    # Maximum length of an individual string rendered inside serialized params
    # and arguments on the dashboard, so very large payloads cannot stall the page.
    MAX_DISPLAY_STRING_LENGTH = 1_000

    CONCURRENCY_CLAIM_BADGE_CLASSES = {
      nil => "text-bg-secondary border border-secondary",
      granted: "text-bg-success border border-success",
      waiting: "bg-warning-subtle text-warning-emphasis border border-warning",
      promoted: "bg-info-subtle text-info-emphasis border border-info",
    }.freeze

    CONCURRENCY_CLAIM_ICONS = {
      granted: "lock_fill",
      waiting: "hourglass_split",
      promoted: "arrow_up_circle_fill",
    }.freeze

    # Renders a job's label as a badge. Labels on which the job has a concurrency claim
    # are colored and prefixed with an icon for the claim's state.
    # Claims are only shown when the job's +concurrency_claims+ are already loaded.
    def job_label_badge(job, label, url: nil)
      claim = job.concurrency_claims.find { |job_claim| job_claim.label == label } if job.association(:concurrency_claims).loaded?
      state_name = claim&.state_name
      truncated_label = truncate(label, length: 15)
      state_text = t(state_name, scope: "good_job.concurrency_claims.states") if state_name
      title = [(label if truncated_label != label), state_text].compact.join(" · ")

      options = { class: "badge font-monospace text-decoration-none #{CONCURRENCY_CLAIM_BADGE_CLASSES.fetch(state_name)}" }
      if title.present?
        options[:title] = title
        options[:data] = { bs_toggle: "tooltip" }
        # Make unlinked badges focusable so keyboard users can reveal the tooltip
        options[:tabindex] = 0 unless url
      end
      content = safe_join([
        (concurrency_claim_icon(state_name) if state_name),
        truncated_label,
        (tag.span(" (#{state_text})", class: "visually-hidden") if state_text),
      ].compact)
      url ? link_to(content, url, **options) : tag.span(content, **options)
    end

    def concurrency_claim_icon(state_name)
      render_icon(CONCURRENCY_CLAIM_ICONS.fetch(state_name), class: "badge-icon me-1", aria: { hidden: true })
    end

    def job_action_states
      {
        reschedule: %w[scheduled retried queued],
        retry: %w[discarded],
        discard: %w[scheduled retried queued],
        force_discard: %w[running],
        destroy: %w[discarded succeeded],
      }
    end

    # Truncates long strings within a JSON-like structure for dashboard display.
    def truncate_display_value(value, limit: MAX_DISPLAY_STRING_LENGTH)
      case value
      when String
        value.length > limit ? "#{value.first(limit)}… [#{value.length} characters total]" : value
      when Array
        value.map { |element| truncate_display_value(element, limit: limit) }
      when Hash
        value.transform_values { |element| truncate_display_value(element, limit: limit) }
      else
        value
      end
    end

    def format_duration(sec)
      return unless sec
      return "" if sec.is_a?(String) # pg interval support added in Rails 6.1

      if sec < 1
        t 'good_job.duration.milliseconds', ms: (sec * 1000).floor
      elsif sec < 10
        t 'good_job.duration.less_than_10_seconds', sec: number_with_delimiter(sec.floor(1))
      elsif sec < 60
        t 'good_job.duration.seconds', sec: sec.floor
      elsif sec < 3600
        t 'good_job.duration.minutes', min: (sec / 60).floor, sec: (sec % 60).floor
      else
        t 'good_job.duration.hours', hour: (sec / 3600).floor, min: ((sec % 3600) / 60).floor
      end
    end

    def format_performance_bucket_size(seconds)
      if seconds >= 365.days && (seconds % 365.days.to_i).zero?
        t "good_job.performance.range.bucket_size.years", count: seconds / 365.days.to_i
      elsif seconds >= 30.days && (seconds % 30.days.to_i).zero?
        t "good_job.performance.range.bucket_size.months", count: seconds / 30.days.to_i
      elsif seconds >= 1.day && (seconds % 1.day.to_i).zero?
        t "good_job.performance.range.bucket_size.days", count: seconds / 1.day.to_i
      elsif (seconds % 1.hour.to_i).zero?
        t "good_job.performance.range.bucket_size.hours", count: seconds / 1.hour.to_i
      elsif (seconds % 1.minute.to_i).zero?
        t "good_job.performance.range.bucket_size.minutes", count: seconds / 1.minute.to_i
      else
        t "good_job.performance.range.bucket_size.seconds", count: seconds
      end
    end

    def relative_time(timestamp, **options)
      options = options.reverse_merge({ scope: "good_job.datetime.distance_in_words" })
      text = t("good_job.helpers.relative_time.#{timestamp.future? ? 'future' : 'past'}", time: time_ago_in_words(timestamp, **options))
      tag.time(text, datetime: timestamp, title: timestamp)
    end

    def number_to_human(count)
      super(count, **translate_hash("good_job.number.human.decimal_units"))
    end

    def number_with_delimiter(count)
      super(count, **translate_hash('good_job.number.format'))
    end

    def translate_hash(key, **options)
      translation_exists?(key, **options) ? translate(key, **options) : {}
    end

    def translation_exists?(key, **options)
      I18n.exists?(scope_key_by_partial(key), **options)
    end
  end
end
