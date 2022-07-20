# frozen_string_literal: true

module GoodJob
  class Setting < ActiveRecord::Base
    CRON_KEYS_DISABLED = "cron_keys_disabled"

    self.table_name = 'good_job_settings'
  end
end
