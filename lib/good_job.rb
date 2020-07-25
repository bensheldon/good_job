require "rails"
require 'good_job/railtie'

require 'good_job/logging'
require 'good_job/lockable'
require 'good_job/job'
require 'good_job/scheduler'
require 'good_job/adapter'
require 'good_job/pg_locks'
require 'good_job/performer'

require 'active_job/queue_adapters/good_job_adapter'

module GoodJob
  mattr_accessor :preserve_job_records, default: false
  mattr_accessor :reperform_jobs_on_standard_error, default: true
  include Logging

  ActiveSupport.run_load_hooks(:good_job, self)
end
