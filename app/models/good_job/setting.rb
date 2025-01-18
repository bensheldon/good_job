# frozen_string_literal: true

module GoodJob
  class Setting < BaseRecord
    CRON_KEYS_ENABLED = "cron_keys_enabled"
    CRON_KEYS_DISABLED = "cron_keys_disabled"
    PAUSED_QUEUES = "paused_queues"
    PAUSED_JOB_CLASSES = "paused_job_classes"

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
      key_string = key.to_s
      enabled_setting = find_or_initialize_by(key: CRON_KEYS_ENABLED) do |record|
        record.value = []
      end
      enabled_setting.value << key unless enabled_setting.value.include?(key_string)
      enabled_setting.save!

      disabled_setting = GoodJob::Setting.find_by(key: CRON_KEYS_DISABLED)
      return unless disabled_setting&.value&.include?(key_string)

      disabled_setting.value.delete(key_string)
      disabled_setting.save!
    end

    def self.cron_key_disable(key)
      enabled_setting = GoodJob::Setting.find_by(key: CRON_KEYS_ENABLED)
      key_string = key.to_s
      if enabled_setting&.value&.include?(key_string)
        enabled_setting.value.delete(key_string)
        enabled_setting.save!
      end

      disabled_setting = find_or_initialize_by(key: CRON_KEYS_DISABLED) do |record|
        record.value = []
      end
      disabled_setting.value << key unless disabled_setting.value.include?(key_string)
      disabled_setting.save!
    end

    def self.pause(queue: nil, job_class: nil)
      raise ArgumentError, "Must provide either queue or job_class, but not both" if queue.nil? == job_class.nil?

      if queue
        setting = find_or_initialize_by(key: PAUSED_QUEUES) do |record|
          record.value = []
        end
        setting.value << queue.to_s unless setting.value.include?(queue.to_s)
      else
        setting = find_or_initialize_by(key: PAUSED_JOB_CLASSES) do |record|
          record.value = []
        end
        setting.value << job_class.to_s unless setting.value.include?(job_class.to_s)
      end
      setting.save!
    end

    def self.unpause(queue: nil, job_class: nil)
      raise ArgumentError, "Must provide either queue or job_class, but not both" if queue.nil? == job_class.nil?

      if queue
        setting = find_by(key: PAUSED_QUEUES)
        return unless setting&.value&.include?(queue.to_s)

        setting.value.delete(queue.to_s)
      else
        setting = find_by(key: PAUSED_JOB_CLASSES)
        return unless setting&.value&.include?(job_class.to_s)

        setting.value.delete(job_class.to_s)
      end
      setting.save!
    end

    def self.paused?(queue: nil, job_class: nil)
      raise ArgumentError, "Must provide either queue or job_class, or neither" if queue && job_class

      if queue
        queue.in? paused(:queues)
      elsif job_class
        job_class.in? paused(:job_classes)
      else
        paused.values.any?
      end
    end

    def self.paused(type = nil)
      if type == :queues
        find_by(key: PAUSED_QUEUES)&.value || []
      elsif type == :job_classes
        find_by(key: PAUSED_JOB_CLASSES)&.value || []
      else
        {
          queues: find_by(key: PAUSED_QUEUES)&.value || [],
          job_classes: find_by(key: PAUSED_JOB_CLASSES)&.value || [],
        }
      end
    end
  end
end
