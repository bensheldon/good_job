if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.skip_paths.push(
    "/favicon.ico",
    "/good_job/assets/"
  )
end
