# frozen_string_literal: true

module GoodJob
  class Setting < BaseRecord
    CRON_KEYS_DISABLED = "cron_keys_disabled"

    self.table_name = 'good_job_settings'

    def self.cron_key_enabled?(key)
      cron_disabled = find_by(key: CRON_KEYS_DISABLED)&.value || []
      cron_disabled.exclude?(key.to_s)
    end

    def self.cron_key_enable(key)
      setting = GoodJob::Setting.find_by(key: CRON_KEYS_DISABLED)
      return unless setting&.value&.include?(key.to_s)

      setting.value.delete(key.to_s)
      setting.save!
    end

    def self.cron_key_disable(key)
      setting = find_or_initialize_by(key: CRON_KEYS_DISABLED) do |record|
        record.value = []
      end
      setting.value << key
      setting.save!
    end
  end
end
