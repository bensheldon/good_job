# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'

if ActiveModel::Type::Boolean.new.cast(ENV.fetch("WARMUP_APP", nil))
  require_relative 'config/warmup'
  warmup do |app|
    # Enable YJIT after boot so workers share the code that warmup compiles (see config/environments/demo.rb)
    RubyVM::YJIT.enable(**YJIT_OPTIONS) if defined?(YJIT_OPTIONS) && defined?(RubyVM::YJIT.enable)
    Warmup.run(app)
  end
end

run Rails.application
Rails.application.load_server if Rails.application.respond_to?(:load_server)
