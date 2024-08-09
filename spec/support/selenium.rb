# frozen_string_literal: true

require "action_dispatch/system_testing/browser"

# Monkeypatch to quiet deprecation notice:
# https://github.com/rails/rails/blob/55c4adeb36eff229972eecbb53723c1b80393091/actionpack/lib/action_dispatch/system_testing/browser.rb#L74
module ActionDispatch
  module SystemTesting
    class Browser # :nodoc:
      silence_redefinition_of_method :resolve_driver_path
      def resolve_driver_path(namespace)
        # The path method has been deprecated in 4.20.0
        namespace::Service.driver_path = if Gem::Version.new(::Selenium::WebDriver::VERSION) >= Gem::Version.new("4.20.0")
                                           ::Selenium::WebDriver::DriverFinder.new(options, namespace::Service.new).driver_path
                                         else
                                           ::Selenium::WebDriver::DriverFinder.path(options, namespace::Service)
                                         end
      end
    end
  end
end
