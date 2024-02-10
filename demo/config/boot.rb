# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __dir__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

begin
  require 'bootsnap/setup'
rescue LoadError
  nil
end

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
