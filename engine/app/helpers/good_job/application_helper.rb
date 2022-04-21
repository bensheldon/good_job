# frozen_string_literal: true
module GoodJob
  module ApplicationHelper
    def relative_time(timestamp)
      text = timestamp.future? ? "in #{time_ago_in_words(timestamp)}" : "#{time_ago_in_words(timestamp)} ago"
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

    def render_icon(name)
      # workaround to render svg icons without all of the log messages
      partial = lookup_context.find_template("good_job/shared/icons/#{name}", [], true)
      partial.render(self, {})
    end
  end
end
