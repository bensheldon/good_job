require "rails"
require 'good_job/railtie'

require 'good_job/configuration'
require 'good_job/log_subscriber'
require 'good_job/lockable'
require 'good_job/job'
require 'good_job/scheduler'
require 'good_job/multi_scheduler'
require 'good_job/adapter'
require 'good_job/pg_locks'
require 'good_job/performer'

require 'active_job/queue_adapters/good_job_adapter'

module GoodJob
  cattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
  mattr_accessor :preserve_job_records, default: false
  mattr_accessor :reperform_jobs_on_standard_error, default: true
  mattr_accessor :on_thread_error, default: nil

  ActiveSupport.run_load_hooks(:good_job, self)
end
