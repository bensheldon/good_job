require 'concurrent/atomic/atomic_boolean'

module GoodJob # :nodoc:
  #
  # Pollers regularly wake up execution threads to check for new work.
  #
  class Poller
    # Defaults for instance of Concurrent::TimerTask.
    # The timer controls how and when sleeping threads check for new work.
    DEFAULT_TIMER_OPTIONS = {
      execution_interval: Configuration::DEFAULT_POLL_INTERVAL,
      timeout_interval: 1,
      run_now: true,
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Pollers in the current process.
    #   @return [array<GoodJob:Poller>]
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

    # @param recipients [Array<#call, Array(Object, Symbol)>]
    # @param poll_interval [Hash] number of seconds between polls
    def initialize(*recipients, poll_interval: nil)
      @recipients = Concurrent::Array.new(recipients)

      @timer_options = DEFAULT_TIMER_OPTIONS.dup
      @timer_options[:execution_interval] = poll_interval if poll_interval.present?

      self.class.instances << self

      create_pool
    end

    # Shut down the poller.
    # If +wait+ is +true+, the poller will wait for background thread to shutdown.
    # If +wait+ is +false+, this method will return immediately even though threads may still be running.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param wait [Boolean] Wait for actively executing threads to finish
    # @return [void]
    def shutdown(wait: true)
      return unless @timer&.running?

      @timer.shutdown
      @timer.wait_for_termination if wait
    end

    # Tests whether the poller is shutdown.
    # @return [true, false, nil]
    def shutdown?
      !@timer&.running?
    end

    # Restart the poller.
    # When shutdown, start; or shutdown and start.
    # @param wait [Boolean] Wait for background thread to finish
    # @return [void]
    def restart(wait: true)
      shutdown(wait: wait)
      create_pool
    end

    # Invoked on completion of TimerTask task.
    # @!visibility private
    # @return [void]
    def timer_observer(time, executed_task, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      instrument("finished_timer_task", { result: executed_task, error: thread_error, time: time })
    end

    private

    def create_pool
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
