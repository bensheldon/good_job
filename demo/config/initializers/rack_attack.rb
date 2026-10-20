# frozen_string_literal: true

# Protect the demo from crawlers that fan out across every job and locale,
# which queue up requests and cause timeouts on a single small dyno.
if defined?(Rack::Attack)
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
  # Loaded in every environment so it can be tested, but only enabled where it's needed
  Rack::Attack.enabled = Rails.env.demo? || Rails.env.production?

  Rack::Attack.throttle("job pages/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.get? && req.path.start_with?("/good_job/jobs/")
  end

  # Action routes only accept PUT/POST, so a GET means a crawler is following links
  ACTION_PATH = %r{\A/good_job/(jobs/[^/]+/(discard|force_discard|reschedule|retry)|batches/[^/]+/retry|cron_entries/[^/]+/(enqueue|enable|disable))\z}

  Rack::Attack.blocklist("action links/ip") do |req|
    Rack::Attack::Fail2Ban.filter("action-links-#{req.ip}", maxretry: 0, findtime: 1.minute, bantime: 1.minute) do
      req.get? && ACTION_PATH.match?(req.path)
    end
  end
end
