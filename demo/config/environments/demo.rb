require_relative 'production'

YJIT_OPTIONS = { mem_size: 16 }.freeze

Rails.application.configure do
  # Cap YJIT's memory in each Puma worker to fit the demo's small dyno.
  # In clustered mode, config/puma.rb enables YJIT in each worker after forking instead,
  # so the master's memory stays untouched by YJIT and shared copy-on-write,
  # and boot and warmup code is never compiled.
  config.yjit = ENV.fetch("WEB_CONCURRENCY", 0).to_i.zero? ? YJIT_OPTIONS : false
end
