require_relative 'production'

Rails.application.configure do
  # Cap YJIT's memory in each Puma worker to fit the demo's small dyno
  config.yjit = { mem_size: 16 }
end
