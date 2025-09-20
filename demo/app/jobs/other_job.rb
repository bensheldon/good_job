class OtherJob < ApplicationJob
  JobError = Class.new(StandardError)

  def perform(*)
    # raise 'nope'
  end
end
