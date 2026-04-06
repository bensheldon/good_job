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

    # with_connection establishes a shared connection context for all AR queries
    # within the example (inner with_connection calls reuse it rather than checking
    # out individual temporary connections). This is important for advisory locks,
    # which are session-scoped: without a shared connection, each query would check
    # out and return its own connection, causing advisory locks to leak back to the pool.
    # Tests that call lease_connection (e.g. via advisory_unlock) promote the connection
    # to sticky; tests that don't will return it cleanly at block end.
    run_example = lambda do
      GoodJob::BaseRecord.connection_pool.with_connection do
        GoodJob::BaseRecord.uncached { example.run }
      end
    end

    if Rails.application.executor.respond_to?(:perform)
      Rails.application.executor.perform(&run_example)
    else
      Rails.application.executor.wrap(&run_example)
    end
  end
end
