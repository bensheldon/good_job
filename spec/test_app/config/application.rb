require_relative 'boot'

require 'rails/all'
require "good_job"
require "good_job/engine"

Bundler.require(*Rails.groups)
require_relative "../lib/thread_name_formatter"

class ThreadNameFormatter < ActiveSupport::Logger::SimpleFormatter
  def emoji_hash(str)
    # Hash the input string using SHA256
    digest = Digest::SHA256.hexdigest(str || "")

    # Take the first few characters from the hash
    partial_digest = digest[0..4].to_i(16)

    # Define the ranges for the emojis
    ranges = [
      (0x1F345..0x1F35E),  # Vegetables and some other food items
      (0x1F400..0x1F43E)   # Animals
    ]

    # Combine all ranges into a single array of code points
    all_emojis = ranges.flat_map { |r| r.to_a }

    # Compute an index within the all_emojis array
    index = partial_digest % all_emojis.length

    # Convert the code point to a character (emoji)
    emoji = [all_emojis[index]].pack('U*')

    emoji
  end

  def call(severity, timestamp, _progname, message)
    prefix = [emoji_hash(Thread.current.name), Thread.current.name, emoji_hash(Thread.current.name)].compact.join(" ")
    "#{ActiveSupport::LogSubscriber.new.send(:color, "[#{prefix}]", :magenta)} #{super}"
  end
end

module TestApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults Gem::Version.new(Rails.version).segments.slice(0..1).join('.').to_f

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    #
    config.log_formatter = ThreadNameFormatter.new

    config.active_job.queue_adapter = :good_job

    # config.middleware.insert_before Rack::Sendfile, ActionDispatch::DebugLocks
    config.log_level = :debug

    config.action_controller.include_all_helpers = false

    config.skylight.environments << 'demo' if defined?(Skylight)

    # Set default locale to something not yet translated for GoodJob
    # config.i18n.available_locales = [:pt]
    # config.i18n.default_locale = :pt
  end
end
