# frozen_string_literal: true

module GoodJob
  module IconsHelper
    STATUS_ICONS = {
      discarded: "exclamation",
      succeeded: "check",
      queued: "dash_circle",
      retried: "arrow_clockwise",
      running: "play",
      scheduled: "clock",
    }.freeze

    STATUS_COLOR = {
      discarded: "danger",
      succeeded: "success",
      queued: "secondary",
      retried: "warning",
      running: "primary",
      scheduled: "secondary",
    }.freeze

    def status_badge(status)
      content_tag :span, status_icon(status, class: "text-white") + t(status, scope: 'good_job.status', count: 1),
                  class: "badge rounded-pill bg-#{STATUS_COLOR.fetch(status)} d-inline-flex gap-2 ps-1 pe-3 align-items-center"
    end

    def status_icon(status, **options)
      options[:class] ||= "text-#{STATUS_COLOR.fetch(status)}"
      icon = render_icon STATUS_ICONS.fetch(status)
      content_tag :span, icon, **options
    end

    def render_icon(name, **options)
      # workaround to render svg icons without all of the log messages
      partial = lookup_context.find_template("good_job/shared/icons/#{name}", [], true)
      options[:class] = Array(options[:class]).join(" ")
      partial.render(self, { class: options[:class] })
    end
  end
end
