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

    def initialize(params = {})
      @params = params.with_indifferent_access
    end

    def key
      params.fetch(:key)
    end
    alias id key

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
      fugit = Fugit::Cron.parse(cron)
      fugit.next_time
    end

    def enqueue
      job_class.constantize.set(set_value).perform_later(*args_value)
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
  end
end
