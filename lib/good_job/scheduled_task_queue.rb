module GoodJob
  class ScheduledTaskQueue
    DEFAULT_MAX_SIZE = 5

    attr_reader :max_size

    def initialize(max_size: nil)
      @max_size = max_size || DEFAULT_MAX_SIZE
      @queue = Concurrent::Array.new
      @mutex = Mutex.new
    end

    def push(scheduled_task)
      @mutex.synchronize do
        queue.select!(&:pending?)

        if max_size.size == 0 || queue.size == max_size && scheduled_task.scheduled_at > queue.last.scheduled_at
          scheduled_task.cancel
          return false
        end

        queue.unshift(scheduled_task)
        queue.sort_by!(&:scheduled_at)

        removed_items = queue.slice!(max_size..-1)
        removed_items&.each(&:cancel)

        true
      end
    end

    def size
      @mutex.synchronize do
        queue.select!(&:pending?)
        queue.size
      end
    end

    private

    attr_reader :queue
  end
end
