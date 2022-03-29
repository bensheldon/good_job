# frozen_string_literal: true
module GoodJob
  class Application < Rails::Application
    config.i18n.available_locales = [:en, :es]
    config.i18n.default_locale = :en
  end
end
