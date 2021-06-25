require 'concurrent/atomic/atomic_boolean'

module GoodJob # :nodoc:
  #
  # Pollers regularly wake up execution threads to check for new work.
  #
  class Poller
    TIMEOUT_INTERVAL = 5

    # Defaults for instance of Concurrent::TimerTask.
    # The timer controls how and when sleeping threads check for new work.
    DEFAULT_TIMER_OPTIONS = {
      execution_interval: Configuration::DEFAULT_POLL_INTERVAL,
      timeout_interval: TIMEOUT_INTERVAL,
      run_now: true,
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Pollers in the current process.
    #   @return [Array<GoodJob::Poller>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    # Creates GoodJob::Poller from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @return [GoodJob::Poller]
    def self.from_configuration(configuration)
      GoodJob::Poller.new(poll_interval: configuration.poll_interval)
    end

    # List of recipients that will receive notifications.
    # @return [Array<#call, Array(Object, Symbol)>]
    attr_reader :recipients

    # @param recipients [Array<Proc, #call, Array(Object, Symbol)>]
    # @param poll_interval [Integer, nil] number of seconds between polls
    def initialize(*recipients, poll_interval: nil)
      @recipients = Concurrent::Array.new(recipients)

      @timer_options = DEFAULT_TIMER_OPTIONS.dup
      @timer_options[:execution_interval] = poll_interval if poll_interval.present?

      self.class.instances << self

      create_timer
    end

    # Tests whether the timer is running.
    # @return [true, false, nil]
    delegate :running?, to: :timer, allow_nil: true

    # Tests whether the timer is shutdown.
    # @return [true, false, nil]
    def shutdown?
      timer ? timer.shutdown? : true
    end

    # Shut down the poller.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [nil, Numeric] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: -1)
      return if timer.nil? || timer.shutdown?

      timer.shutdown if timer.running?

      if timer.shuttingdown? && timeout # rubocop:disable Style/GuardClause
        timer_wait = timeout.negative? ? nil : timeout
        timer.kill unless timer.wait_for_termination(timer_wait)
      end
    end

    # Restart the poller.
    # When shutdown, start; or shutdown and start.
    # @param timeout [Numeric, nil] Seconds to wait; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      shutdown(timeout: timeout) if running?
      create_timer
    end

    # Invoked on completion of TimerTask task.
    # @!visibility private
    # @param time [Integer]
    # @param executed_task [Object, nil]
    # @param thread_error [Exception, nil]
    # @return [void]
    def timer_observer(time, executed_task, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      ActiveSupport::Notifications.instrument("finished_timer_task", { result: executed_task, error: thread_error, time: time })
    end

    private

    # @return [Concurrent::TimerTask]
    attr_reader :timer

    # @return [void]
    def create_timer
      return if @timer_options[:execution_interval] <= 0

      @timer = Concurrent::TimerTask.new(@timer_options) do
        recipients.each do |recipient|
          target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
          target.send(method_name)
        end
      end
      @timer.add_observer(self, :timer_observer)
      @timer.execute
    end
  end
end
