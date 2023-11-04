class FragileJob < ApplicationJob
  FragileError = Class.new(StandardError)
  FAILURE_RATE = 0.6

  def perform
    raise FragileError if FAILURE_RATE <= rand
  end
end
