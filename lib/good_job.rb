require "rails"
require 'good_job/railtie'

require 'good_job/logging'
require 'good_job/lockable'
require 'good_job/job'
require 'good_job/inline_scheduler'
require "good_job/scheduler"
require "good_job/job_wrapper"
require 'good_job/adapter'

module GoodJob
  include Logging

  ActiveSupport.run_load_hooks(:good_job, self)
end
