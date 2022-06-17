# frozen_string_literal: true
module GoodJob
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    around_action :switch_locale

    content_security_policy do |policy|
      policy.default_src(:none) if policy.default_src(*policy.default_src).blank?
      policy.connect_src(:self) if policy.connect_src(*policy.connect_src).blank?
      policy.base_uri(:none) if policy.base_uri(*policy.base_uri).blank?
      policy.font_src(:self) if policy.font_src(*policy.font_src).blank?
      policy.img_src(:self, :data) if policy.img_src(*policy.img_src).blank?
      policy.object_src(:none) if policy.object_src(*policy.object_src).blank?
      policy.script_src(:self) if policy.script_src(*policy.script_src).blank?
      policy.style_src(:self) if policy.style_src(*policy.style_src).blank?
      policy.form_action(:self) if policy.form_action(*policy.form_action).blank?
      policy.frame_ancestors(:none) if policy.frame_ancestors(*policy.frame_ancestors).blank?
    end

    before_action do
      next if request.content_security_policy_nonce_generator

      request.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
    end

    private

    def default_url_options(options = {})
      { locale: I18n.locale }.merge(options)
    end

    def switch_locale(&action)
      I18n.with_locale(current_locale, &action)
    end

    def current_locale
      if params[:locale]
        params[:locale]
      elsif good_job_available_locales.exclude?(I18n.default_locale) && I18n.available_locales.include?(:en)
        :en
      else
        I18n.default_locale
      end
    end

    def good_job_available_locales
      @_good_job_available_locales ||= GoodJob::Engine.root.join("config/locales").glob("*.yml").map { |path| File.basename(path, ".yml").to_sym }.uniq
    end
  end
end
