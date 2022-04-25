# frozen_string_literal: true
module GoodJob
  module ApplicationHelper
    def duration(sec)
      return unless sec

      if sec < 1
        format "%dms", sec * 1000
      elsif sec < 10
        format "%.2fs", sec
      elsif sec < 60
        format "%ds", sec
      elsif sec < 3600
        format "%dm%ds", sec / 60, sec % 60
      else
        format "%dh%dm", sec / 3600, (sec % 3600) / 60
      end
    end

    def relative_time(timestamp, **args)
      text = timestamp.future? ? "in #{time_ago_in_words(timestamp, **args)}" : "#{time_ago_in_words(timestamp, **args)} ago"
      tag.time(text, datetime: timestamp, title: timestamp)
    end

    STATUS_ICONS = {
      discarded: "exclamation",
      finished: "check",
      queued: "clock",
      retried: "arrow_clockwise",
      running: "play",
      scheduled: "clock",
    }.freeze

    STATUS_COLOR = {
      discarded: "danger",
      finished: "success",
      queued: "secondary",
      retried: "secondary",
      running: "primary",
      scheduled: "secondary",
    }.freeze

    def status_badge(status)
      content_tag :span, status_icon(status, class: "text-white") + status.to_s.titleize,
                  class: "badge rounded-pill bg-#{STATUS_COLOR.fetch(status)} d-inline-flex gap-2 ps-1 pe-3 align-items-center"
    end

    def status_icon(status, **options)
      options[:class] ||= "text-#{STATUS_COLOR.fetch(status)}"
      icon = render("good_job/shared/icons/#{STATUS_ICONS.fetch(status)}")
      content_tag :span, icon, **options
    end
  end
end
