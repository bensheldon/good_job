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

    def language_options
      available_languages.map { |locale| language_option(locale) }.join
    end

    def language_option(locale)
      link_to locale, url_for(locale: locale), class: "dropdown-item"
    end

    def available_languages
      I18n.available_locales.reject { |locale| locale == I18n.locale }
    end
  end
end
