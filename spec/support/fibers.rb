# frozen_string_literal: true

RSpec.configure do |c|
  if ENV['GOOD_JOB_REQUIRE_FIBERS'] == '1'
    raise 'GOOD_JOB_REQUIRE_FIBERS=1 requires Ruby and Async versions that support fibers' unless GoodJob::Scheduler.fiber_execution_supported?
    raise 'GOOD_JOB_REQUIRE_FIBERS=1 requires Rails fiber isolation' unless defined?(ActiveSupport::IsolatedExecutionState)
  end

  unless GoodJob::Scheduler.fiber_execution_supported?
    puts "Skipping fiber specs: unsupported Ruby or Async version"
    c.filter_run_excluding :requires_async
  end

  if defined?(ActiveSupport::IsolatedExecutionState)
    c.around(:example, :fiber_isolation) do |example|
      original_isolation_level = ActiveSupport::IsolatedExecutionState.isolation_level
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      example.run
    ensure
      ActiveSupport::IsolatedExecutionState.isolation_level = original_isolation_level
    end
  else
    puts "Skipping fiber isolation specs: unsupported Rails version"
    c.filter_run_excluding :fiber_isolation
  end
end
