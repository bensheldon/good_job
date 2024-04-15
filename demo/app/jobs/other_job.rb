require_relative '../../../lib/good_job/active_job_extensions/paused_options'

class OtherJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::PausedOptions
  JobError = Class.new(StandardError)

  def perform(*)
    # raise 'nope'
  end
end
