# frozen_string_literal: true

require "capybara/cuprite"

Capybara.default_max_wait_time = 5
Capybara.disable_animation = true
Capybara.server = :puma, { Silent: true }

module SystemTestHelpers
  def js_driver?
    Capybara.current_driver != :rack_test
  end

  [
    :accept_alert,
    :dismiss_alert,
    :accept_confirm,
    :dismiss_confirm,
    :accept_prompt,
    :dismiss_prompt,
    :accept_modal,
    :dismiss_modal,
  ].each do |method|
    module_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{method}(...)                 # def accept_alert(...)
          return yield unless js_driver?   #   return yield unless js_driver?
          super                            #   super
        end                                # end
    RUBY
  end
end

RSpec.configure do |config|
  config.include ActionView::RecordIdentifier, type: :system
  config.include SystemTestHelpers, type: :system

  config.before(:each, type: :system) do |example|
    example.metadata[:js] = true if ENV['SHOW_BROWSER']

    if example.metadata[:js]
      Capybara.session_options.automatic_label_click = true

      # Chrome's no-sandbox option is required for running in Docker
      driven_by(
        :cuprite,
        screen_size: [1024, 800],
        options: {
          process_timeout: 30,
          headless: ENV['SHOW_BROWSER'] ? false : true,
          slowmo: ENV["SLOWMO"]&.to_f,
          browser_options: ENV["DOCKER"] || ENV["CI"] ? { "no-sandbox" => nil } : {},
        }
      )
    else
      Capybara.session_options.automatic_label_click = false
      driven_by :rack_test
    end
  end
end
