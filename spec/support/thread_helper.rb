# frozen_string_literal: true

module ThreadHelper
  def rails_promise(*args)
    wrapped_task = proc do |*proc_args|
      Rails.application.executor.wrap { yield(*proc_args) }
    end
    Concurrent::Promises.future(*args, &wrapped_task)
  end
end

RSpec.configure { |c| c.include ThreadHelper }
