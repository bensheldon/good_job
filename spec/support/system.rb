# frozen_string_literal: true
require "selenium-webdriver"

Capybara.default_max_wait_time = 2
Capybara.server = :puma, { Silent: true }
Capybara.disable_animation = true

module SystemTestHelpers
  [
    :accept_alert,
    :dismiss_alert,
    :accept_confirm,
    :dismiss_confirm,
    :accept_prompt,
    :dismiss_prompt,
    :accept_modal,
    :dismiss_modal,
  ].each do |driver_method|
    define_method(driver_method) do |text = nil, **options, &blk|
      super(text, **options, &blk)
    rescue Capybara::NotSupportedByDriverError
      blk.call
    end
  end
end

RSpec.configure do |config|
  config.include ActionView::RecordIdentifier, type: :system
  config.include SystemTestHelpers, type: :system

  config.before(:each, type: :system) do |example|
    if ENV['SHOW_BROWSER']
      example.metadata[:js] = true
      driven_by :selenium, using: :chrome, screen_size: [1024, 800]
    else
      driven_by :rack_test
    end
  end

  config.before(:each, type: :system, js: true) do
    # Chrome's no-sandbox option is required for running in Docker
    driven_by :selenium, using: (ENV['SHOW_BROWSER'] ? :chrome : :headless_chrome), screen_size: [1024, 800] do |driver_options|
      driver_options.add_argument("--disable-dev-shm-usage")
      driver_options.add_argument("--no-sandbox")
    end
  end

  config.after(:each, type: :system, js: true) do |example|
    @previous_browser_logs ||= []

    if example.exception
      browser_logs = page.driver.browser.manage.logs.get(:browser) - @previous_browser_logs
      raise "Browser logs:\n\n#{browser_logs.join("\n")}" unless browser_logs.empty?
    end
    @previous_browser_logs = page.driver.browser.manage.logs.get(:browser)
  end
end
