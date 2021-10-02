# frozen_string_literal: true
module GoodJob
  module ApplicationHelper
    def relative_time(timestamp)
      text = timestamp.future? ? "in #{time_ago_in_words(timestamp)}" : "#{time_ago_in_words(timestamp)} ago"
      tag.time(text, datetime: timestamp, title: timestamp)
    end
  end
end
