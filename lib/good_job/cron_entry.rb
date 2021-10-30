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
      configuration ||= GoodJob::Configuration.new({})
      configuration.cron_entries
    end

    def self.find(key, configuration: nil)
      all(configuration: configuration).find { |entry| entry.key == key.to_sym }.tap do |cron_entry|
        raise ActiveRecord::RecordNotFound unless cron_entry
      end
    end

    def initialize(params = {})
      @params = params

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

    def cron
      params.fetch(:cron)
    end

    def set
      params[:set]
    end

    def args
      params[:args]
    end

    def description
      params[:description]
    end

    def next_at
      fugit.next_time.to_t
    end

    def schedule
      fugit.original
    end

    def fugit
      @_fugit ||= Fugit.parse(cron)
    end

    def jobs
      GoodJob::ActiveJobJob.where(cron_key: key)
    end

    def last_at
      return if last_job.blank?

      if GoodJob::ActiveJobJob.column_names.include?('cron_at')
        (last_job.cron_at || last_job.created_at).localtime
      else
        last_job.created_at
      end
    end

    def enqueue(cron_at = nil)
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.cron_key = key
        current_thread.cron_at = cron_at

        job_class.constantize.set(set_value).perform_later(*args_value)
      end
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def last_job
      if GoodJob::ActiveJobJob.column_names.include?('cron_at')
        jobs.order("cron_at DESC NULLS LAST").first
      else
        jobs.order(created_at: :asc).last
      end
    end

    def display_properties
      {
        key: key,
        class: job_class,
        cron: schedule,
        set: display_property(set),
        args: display_property(args),
        description: display_property(description),
      }
    end

    private

    def set_value
      value = set || {}
      value.respond_to?(:call) ? value.call : value
    end

    def args_value
      value = args || []
      value.respond_to?(:call) ? value.call : value
    end

    def display_property(value)
      case value
      when NilClass
        "None"
      when Proc
        "Lambda/Callable"
      else
        value
      end
    end
  end
end
