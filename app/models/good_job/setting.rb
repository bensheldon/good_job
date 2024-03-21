# frozen_string_literal: true

module GoodJob
  class Setting < BaseRecord
    CRON_KEYS_ENABLED = "cron_keys_enabled"
    CRON_KEYS_DISABLED = "cron_keys_disabled"

    self.table_name = 'good_job_settings'
    self.implicit_order_column = 'created_at'

    def self.cron_key_enabled?(key, default: true)
      if default
        cron_disabled = find_by(key: CRON_KEYS_DISABLED)&.value || []
        cron_disabled.exclude?(key.to_s)
      else
        cron_enabled = find_by(key: CRON_KEYS_ENABLED)&.value || []
        cron_enabled.include?(key.to_s)
      end
    end

    def self.cron_key_enable(key)
      enabled_setting = find_or_initialize_by(key: CRON_KEYS_ENABLED) do |record|
        record.value = []
      end
      enabled_setting.value << key unless enabled_setting.value.include?(key)
      enabled_setting.save!

      disabled_setting = GoodJob::Setting.find_by(key: CRON_KEYS_DISABLED)
      return unless disabled_setting&.value&.include?(key.to_s)

      disabled_setting.value.delete(key.to_s)
      disabled_setting.save!
    end

    def self.cron_key_disable(key)
      enabled_setting = GoodJob::Setting.find_by(key: CRON_KEYS_ENABLED)
      if enabled_setting&.value&.include?(key.to_s)
        enabled_setting.value.delete(key.to_s)
        enabled_setting.save!
      end

      disabled_setting = find_or_initialize_by(key: CRON_KEYS_DISABLED) do |record|
        record.value = []
      end
      disabled_setting.value << key unless disabled_setting.value.include?(key)
      disabled_setting.save!
    end
  end
end
