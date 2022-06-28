module GoodJob
  class CronEntryStatus < ActiveRecord::Base
    self.table_name = 'good_jobs_cron'

    def self.init!
      GoodJob::CronEntry.all.each do |ce|
        cs = where(key: ce.key).first_or_create!
      end
    end
  end
end
