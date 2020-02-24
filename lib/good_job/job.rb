module GoodJob
  class Job < ActiveRecord::Base
    include Lockable
    self.table_name = 'good_jobs'
  end
end
