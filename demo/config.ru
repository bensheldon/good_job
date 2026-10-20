# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'

if Rails.env.demo?
  require_relative 'lib/warmup'
  warmup { |app| Warmup.run(app) }
end

run Rails.application
Rails.application.load_server if Rails.application.respond_to?(:load_server)
