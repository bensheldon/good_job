# frozen_string_literal: true

module GoodJob
  module ApplicationHelper
    # Explicit helper inclusion because ApplicationController inherits from the host app.
    #
    # We can't rely on +config.action_controller.include_all_helpers = true+ in the host app.
    include IconsHelper

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
