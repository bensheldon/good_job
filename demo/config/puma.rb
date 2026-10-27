# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
port        ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
#
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Specifies the number of `workers` to boot in clustered mode.
# Workers are forked web server processes. If using threads and workers together
# the concurrency of the application would be max `threads` * `workers`.
# Workers do not work on JRuby or Windows (both of which do not support
# processes).
#
web_concurrency = ENV.fetch("WEB_CONCURRENCY") { 0 }.to_i
workers web_concurrency

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
#
preload_app! if ENV["PRELOAD_APP"]

# rbtrace doesn't survive a fork, so clustered workers require it after forking
# (config/initializers/rbtrace.rb skips it in the master).
# This can run before Rails loads, so don't use ActiveModel here.
rbtrace = %w[1 true yes on].include?(ENV.fetch("RBTRACE", "").downcase)

before_fork do
  GoodJob.shutdown
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  # Compact the heap and free unused pages so forked workers share as much memory as possible
  Process.warmup if Process.respond_to?(:warmup)
end if web_concurrency > 0

# Puma 7+ renamed on_worker_boot/on_worker_shutdown
public_send(respond_to?(:before_worker_boot) ? :before_worker_boot : :on_worker_boot) do
  require "rbtrace" if rbtrace
  # Without preload_app!, each worker boots the app and GoodJob starts itself;
  # only a preloaded app needs GoodJob restarted after the fork.
  GoodJob.restart if ENV["PRELOAD_APP"] && defined?(GoodJob)
end if web_concurrency > 0

public_send(respond_to?(:before_worker_shutdown) ? :before_worker_shutdown : :on_worker_shutdown) do
  GoodJob.shutdown
end if web_concurrency > 0

# Run a minor GC between requests so it doesn't happen during one
out_of_band do
  GC.start(full_mark: false, immediate_sweep: false)
end

# Thruster keeps idle connections to Puma open for HTTP_IDLE_TIMEOUT (default 60s),
# so Puma must not close them first or Thruster will get errors reusing them.
max_keep_alive Float::INFINITY if respond_to?(:max_keep_alive) # Puma 7+
persistent_timeout ENV.fetch("THRUSTER_HTTP_IDLE_TIMEOUT", 60).to_i + 5

MAIN_PID = Process.pid
at_exit do
  GoodJob.shutdown if Process.pid == MAIN_PID
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
