# frozen_string_literal: true

# Wraps each example in a Rails Executor
# This more closely matches the behavior of Rails Minitest helpers:
#
# https://github.com/rails/rails/pull/43550
#
# This also avoids the issue of Active Job wrapping ActiveJob::Base#execute
# with its own Reloader, which causes database connections to be dropped if
# there is not already an executor/reloader in place.
#
RSpec.configure do |config|
  config.around do |example|
    next example.run if example.metadata[:without_executor]

    if Rails.application.executor.respond_to?(:perform)
      Rails.application.executor.perform do
        ActiveRecord::Base.connection.disable_query_cache!
        example.run
      end
    else
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection.disable_query_cache!
        example.run
      end
    end
  end
end
