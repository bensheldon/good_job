# frozen_string_literal: true

module GoodJob
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    around_action :use_good_job_locale

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

    def use_good_job_locale(&action)
      @original_i18n_config = I18n.config
      I18n.config = ::GoodJob::I18nConfig.new
      I18n.with_locale(current_locale, &action)
    ensure
      I18n.config = @original_i18n_config
      @original_i18n_config = nil
    end

    def use_original_locale
      prev_config = I18n.config
      I18n.config = @original_i18n_config if @original_i18n_config
      yield
    ensure
      I18n.config = prev_config
    end

    def current_locale
      if request.GET['locale']
        request.GET['locale']
      elsif params[:locale]
        params[:locale]
      else
        I18n.default_locale
      end
    end

    ActiveSupport.run_load_hooks(:good_job_application_controller, self)
  end
end
