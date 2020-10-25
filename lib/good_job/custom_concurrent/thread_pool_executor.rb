require "concurrent/executor/thread_pool_executor"

module GoodJob
  module CustomConcurrent
    # Custom sub-class of +Concurrent::ThreadPoolExecutor+ to add additional worker status.
    # @private
    class ThreadPoolExecutor < Concurrent::ThreadPoolExecutor
      # Number of inactive threads available to execute tasks.
      # https://github.com/ruby-concurrency/concurrent-ruby/issues/684#issuecomment-427594437
      # @return [Integer]
      def ready_worker_count
        synchronize do
          workers_still_to_be_created = @max_length - @pool.length
          workers_created_but_waiting = @ready.length

          workers_still_to_be_created + workers_created_but_waiting
        end
      end
    end
  end
end
