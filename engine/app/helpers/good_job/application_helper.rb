# frozen_string_literal: true
module GoodJob
  module ApplicationHelper
    def relative_time(timestamp, **args)
      text = timestamp.future? ? "in #{time_ago_in_words(timestamp, **args)}" : "#{time_ago_in_words(timestamp, **args)} ago"
      tag.time(text, datetime: timestamp, title: timestamp)
    end

    def status_badge(status)
      classes = case status
                when :finished
                  "badge rounded-pill bg-success"
                when :queued, :scheduled, :retried
                  "badge rounded-pill bg-secondary"
                when :running
                  "badge rounded-pill bg-primary"
                when :discarded
                  "badge rounded-pill bg-danger"
                end

      content_tag :span, status.to_s, class: classes
    end
  end
end
