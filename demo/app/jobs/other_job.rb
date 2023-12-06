class OtherJob < ApplicationJob
  JobError = Class.new(StandardError)

  def perform(*)
  end
end
