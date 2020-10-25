module GoodJob
  module CustomConcurrent
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
