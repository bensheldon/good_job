# frozen_string_literal: true

# Protect the demo from crawlers that fan out across every job and locale,
# which queue up requests and cause timeouts on a single small dyno.
if defined?(Rack::Attack)
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)

  Rack::Attack.throttle("job pages/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.get? && req.path.start_with?("/good_job/jobs/")
  end
end
