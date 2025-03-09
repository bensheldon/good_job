# frozen_string_literal: true

require "concurrent/hash"
require "concurrent/scheduled_task"
require "fugit"

module GoodJob # :nodoc:
  #
  # A CronEntry represents a single scheduled item's properties.
  #
  class CronEntry
    include ActiveModel::Model

    attr_reader :params

    def self.all(configuration: nil)
      configuration ||= GoodJob.configuration
      configuration.cron_entries
    end

    def self.find(key, configuration: nil)
      all(configuration: configuration).find { |entry| entry.key == key.to_sym }.tap do |cron_entry|
        raise ActiveRecord::RecordNotFound unless cron_entry
      end
    end

    def initialize(params = {})
      @params = params

      return if cron_proc?
      raise ArgumentError, "Invalid cron format: '#{cron}'" unless fugit.instance_of?(Fugit::Cron)
    end

    def key
      params.fetch(:key)
    end

    alias id key
    alias to_param key

    def job_class
      params.fetch(:class)
    end

    def set
      params[:set]
    end

    def args
      params[:args]
    end

    def kwargs
      params[:kwargs]
    end

    def description
      params[:description]
    end

    def next_at(previously_at: nil)
      if cron_proc?
        result = Rails.application.executor.wrap { cron.call(previously_at || last_job_at) }
        if result.is_a?(String)
          Fugit.parse(result).next_time.to_t
        else
          result
        end
      else
        fugit.next_time.to_t
      end
    end

    def within(period, previously_at: nil)
      if cron_proc?
        result = Rails.application.executor.wrap { cron.call(previously_at || last_job_at) }
        if result.is_a?(String)
          Fugit.parse(result).within(period).map(&:to_t)
        else
          result
        end
      else
        fugit.within(period).map(&:to_t)
      end
    end

    def enabled?
      GoodJob::Setting.cron_key_enabled?(key, default: enabled_by_default?)
    end

    def enable
      GoodJob::Setting.cron_key_enable(key)
    end

    def disable
      GoodJob::Setting.cron_key_disable(key)
    end

    def enqueue(cron_at = nil)
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.cron_key = key
        current_thread.cron_at = cron_at

        I18n.with_locale(I18n.default_locale) do
          job_klass = job_class_value
          job_klass = job_klass.constantize if job_klass.is_a?(String)
          next unless job_klass.is_a?(Class)

          configured_job = job_klass.set(set_value)
          kwargs_value.present? ? configured_job.perform_later(*args_value, **kwargs_value) : configured_job.perform_later(*args_value)
        end
      end
    end

    def display_properties
      {
        key: key,
        class: job_class,
        cron: display_schedule,
        set: display_property(set),
        description: display_property(description),
      }.tap do |properties|
        properties[:class] = display_property(job_class) if job_class.present?
        properties[:args] = display_property(args) if args.present?
        properties[:kwargs] = display_property(kwargs) if kwargs.present?
      end
    end

    def display_schedule
      cron_proc? ? display_property(cron) : fugit.original
    end

    def jobs
      GoodJob::Job.where(cron_key: key)
    end

    def last_job
      jobs.order("cron_at DESC NULLS LAST").first
    end

    def last_job_at
      return if last_job.blank?

      (last_job.cron_at || last_job.created_at).localtime
    end

    private

    def enabled_by_default?
      value = params.fetch(:enabled_by_default, true)
      value.respond_to?(:call) ? value.call : value
    end

    def cron
      params.fetch(:cron)
    end

    def cron_proc?
      cron.respond_to?(:call)
    end

    def fugit
      @_fugit ||= Fugit.parse(cron)
    end

    def job_class_value
      value = job_class || nil
      value.respond_to?(:call) ? value.call : value
    end

    def set_value
      value = set || {}
      value.respond_to?(:call) ? value.call : value
    end

    def args_value
      value = args || []
      value.respond_to?(:call) ? value.call : value
    end

    def kwargs_value
      value = kwargs || nil
      value.respond_to?(:call) ? value.call : value
    end

    def display_property(value)
      case value
      when NilClass
        "None"
      when Callable
        "Lambda/Callable"
      else
        value
      end
    end
  end
end
