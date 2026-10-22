require_relative 'production'

YJIT_OPTIONS = { mem_size: 16 }.freeze

Rails.application.configure do
  # Cap YJIT's memory in each Puma worker to fit the demo's small dyno.
  # When warming up, config.ru enables YJIT after boot instead, so boot code isn't
  # compiled but the code warmup runs is compiled in the master and shared by workers.
  config.yjit = ActiveModel::Type::Boolean.new.cast(ENV.fetch("WARMUP_APP", nil)) ? false : YJIT_OPTIONS
end
