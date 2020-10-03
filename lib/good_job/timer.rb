module GoodJob
  #
  # Timers will wake at the provided times to check for new work.
  #
  # Timers manage a discrete set of wake up times, sorted by soonest.
  # New times can be pushed onto a Timer, and they will added if they are
  # sooner than existing tracked times, or discarded if they are later than
  # existing tracked times and the Timer's queue of tracked times is full.
  #
  # @todo Allow Timer to track an unbounded number of wake times.
  #
  # Timers are intended to be used with a {GoodJob::Scheduler} to provide
  # reduced execution scheduling latency compared to a {GoodJob::Poller}.
  #
  class Timer
    # Default number of wake times to track
    DEFAULT_MAX_QUEUE = 5

    # Defaults for instance of +Concurrent::ThreadPoolExecutor+.
    EXECUTOR_OPTIONS = {
      name: 'timer',
      min_threads: 0,
      max_threads: 1,
      auto_terminate: true,
      idletime: 60,
      max_queue: 0,
      fallback_policy: :discard, # shouldn't matter -- 0 max queue
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Timers in the current process.
    #   @return [array<GoodJob:Timer>]
    cattr_reader :instances, default: [], instance_reader: false

    # @!attribute [r] queue
    #   List of scheduled wakeups.
    #   @return [GoodJob::Timer::ScheduleTask]
    attr_reader :queue

    # @!attribute [r] queue
    #   Number of wake times to track.
    #   @return [Integer]
    attr_reader :max_queue

    # List of recipients that will receive wakeups.
    # @return [Array<#call, Array(Object, Symbol)>]
    attr_reader :recipients

    # @param recipients [Array<#call, Array(Object, Symbol)>]
    # @param max_queue [nil, Integer] Maximum number of times to track
    def initialize(*recipients, max_queue: nil)
      @recipients = Concurrent::Array.new(recipients)
      @max_queue = max_queue || DEFAULT_MAX_QUEUE
      @queue = Concurrent::Array.new
      @mutex = Mutex.new

      self.class.instances << self

      create_executor
    end

    # Add a wake time to be tracked.
    # The timestamp value be be discarded it is not sooner than the
    # @param timestamp [Time, DateTime] the wake time
    def push(timestamp)
      @mutex.synchronize do
        queue.select!(&:pending?)
        return if queue.size == max_queue && timestamp > queue.last.scheduled_at

        task = ScheduledTask.new(timestamp, args: [@recipients], executor: @executor) do |recipients|
          recipients.each do |recipient|
            target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
            target.send(method_name)
          end
        end
        task.execute

        queue.unshift(task)
        queue.sort_by!(&:scheduled_at)

        removed_items = queue.slice!(max_queue..-1)
        removed_items&.each(&:cancel)

        task
      end
    end

    # Shut down the timer.
    def shutdown(wait: true)
      return unless @executor&.running?

      @executor.shutdown
      @executor.wait_for_termination if wait
    end

    private

    def create_executor
      @executor = Concurrent::ThreadPoolExecutor.new(EXECUTOR_OPTIONS)
    end

    class ScheduledTask < Concurrent::ScheduledTask
      attr_reader :scheduled_at

      def initialize(timestamp, **args, &block)
        @scheduled_at = timestamp

        delay = [(timestamp - Time.current).to_f, 0].max
        super(delay, **args, &block)
      end
    end
  end
end
