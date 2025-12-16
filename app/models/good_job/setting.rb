# frozen_string_literal: true

module GoodJob
  class Setting < BaseRecord
    CRON_KEYS_ENABLED = "cron_keys_enabled"
    CRON_KEYS_DISABLED = "cron_keys_disabled"
    PAUSES = "pauses"

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

    def self.pause(queue: nil, job_class: nil, label: nil)
      raise ArgumentError, "Must provide exactly one of queue, job_class, or label" unless [queue, job_class, label].one?(&:present?)

      setting = find_or_initialize_by(key: PAUSES) do |record|
        record.value = { "queues" => [], "job_classes" => [], "labels" => [] }
      end

      if queue
        setting.value["queues"] ||= []
        setting.value["queues"] << queue.to_s unless setting.value["queues"].include?(queue.to_s)
      elsif job_class
        setting.value["job_classes"] ||= []
        setting.value["job_classes"] << job_class.to_s unless setting.value["job_classes"].include?(job_class.to_s)
      else
        setting.value["labels"] ||= []
        setting.value["labels"] << label.to_s unless setting.value["labels"].include?(label.to_s)
      end
      setting.save!
    end

    def self.unpause(queue: nil, job_class: nil, label: nil)
      raise ArgumentError, "Must provide exactly one of queue, job_class, or label" unless [queue, job_class, label].one?(&:present?)

      setting = find_by(key: PAUSES)
      return unless setting

      if queue
        return unless setting.value["queues"]&.include?(queue.to_s)

        setting.value["queues"].delete(queue.to_s)
      elsif job_class
        return unless setting.value["job_classes"]&.include?(job_class.to_s)

        setting.value["job_classes"].delete(job_class.to_s)
      else
        return unless setting.value["labels"]&.include?(label.to_s)

        setting.value["labels"].delete(label.to_s)
      end
      setting.save!
    end

    def self.paused?(queue: nil, job_class: nil, label: nil)
      raise ArgumentError, "Must provide at most one of queue, job_class, or label" if [queue, job_class, label].many?(&:present?)

      if queue
        queue.in? paused(:queues)
      elsif job_class
        job_class.in? paused(:job_classes)
      elsif label
        label.in? paused(:labels)
      else
        paused.values.any?(&:any?)
      end
    end

    def self.paused(type = nil)
      setting = find_by(key: PAUSES)
      pauses = setting&.value&.deep_dup || { "queues" => [], "job_classes" => [], "labels" => [] }
      pauses = pauses.with_indifferent_access

      case type
      when :queues
        pauses["queues"]
      when :job_classes
        pauses["job_classes"]
      when :labels
        pauses["labels"]
      else
        {
          queues: pauses["queues"] || [],
          job_classes: pauses["job_classes"] || [],
          labels: pauses["labels"] || [],
        }
      end
    end
  end
end

ActiveSupport.run_load_hooks(:good_job_setting, GoodJob::Setting)
