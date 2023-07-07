# frozen_string_literal: true

module GoodJob
  class I18nConfig < ::I18n::Config
    BACKEND = I18n::Backend::Simple.new
    AVAILABLE_LOCALES = GoodJob::Engine.root.join("config/locales").glob("*.yml").map { |path| File.basename(path, ".yml").to_sym }.uniq
    AVAILABLE_LOCALES_SET = AVAILABLE_LOCALES.inject(Set.new) { |set, locale| set << locale.to_s << locale.to_sym }

    def backend
      BACKEND
    end

    def available_locales
      AVAILABLE_LOCALES
    end

    def available_locales_set
      AVAILABLE_LOCALES_SET
    end

    def default_locale
      GoodJob.configuration.dashboard_default_locale
    end
  end
end
