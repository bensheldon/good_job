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
      content_tag :span, status_icon(status) + t(status, scope: 'good_job.status', count: 1),
                  class: "badge rounded-pill text-bg-#{STATUS_COLOR.fetch(status)} d-inline-flex gap-2 ps-1 pe-3 align-items-center"
    end

    def status_icon(status, **options)
      icon = render_icon STATUS_ICONS.fetch(status)
      content_tag :span, icon, **options
    end

    def render_icon(name, class: nil, **options)
      tag.svg(viewBox: "0 0 16 16", class: "svg-icon #{binding.local_variable_get(:class)}", **options) do
        tag.use(fill: "currentColor", href: "#{icons_path}##{name}")
      end
    end

    def icons_path
      @_icons_path ||= frontend_static_path(:icons, format: :svg, locale: nil)
    end
  end
end
