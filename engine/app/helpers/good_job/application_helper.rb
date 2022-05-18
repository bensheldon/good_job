# frozen_string_literal: true
module GoodJob
  module ApplicationHelper
    def format_duration(sec)
      return unless sec

      if sec < 1
        t 'duration.milliseconds', ms: (sec * 1000).floor
      elsif sec < 10
        t 'duration.less_than_10_seconds', sec: sec.floor
      elsif sec < 60
        t 'duration.seconds', sec: sec.floor
      elsif sec < 3600
        t 'duration.minutes', min: (sec / 60).floor, sec: (sec % 60).floor
      else
        t 'duration.hours', hour: (sec / 3600).floor, min: ((sec % 3600) / 60).floor
      end
    end

    def relative_time(timestamp, **args)
      text = timestamp.future? ? "in #{time_ago_in_words(timestamp, **args)}" : "#{time_ago_in_words(timestamp, **args)} ago"
      tag.time(text, datetime: timestamp, title: timestamp)
    end

    STATUS_ICONS = {
      discarded: "exclamation",
      finished: "check",
      queued: "dash_circle",
      retried: "arrow_clockwise",
      running: "play",
      scheduled: "clock",
    }.freeze

    STATUS_COLOR = {
      discarded: "danger",
      finished: "success",
      queued: "warning",
      retried: "secondary",
      running: "primary",
      scheduled: "secondary",
    }.freeze

    def status_badge(status)
      content_tag :span, status_icon(status, class: "text-white") + t(status, scope: '.status'),
                  class: "badge rounded-pill bg-#{STATUS_COLOR.fetch(status)} d-inline-flex gap-2 ps-1 pe-3 align-items-center"
    end

    def status_icon(status, **options)
      options[:class] ||= "text-#{STATUS_COLOR.fetch(status)}"
      icon = render_icon STATUS_ICONS.fetch(status)
      content_tag :span, icon, **options
    end

    def render_icon(name)
      # workaround to render svg icons without all of the log messages
      partial = lookup_context.find_template("good_job/shared/icons/#{name}", [], true)
      partial.render(self, {})
    end
  end
end
