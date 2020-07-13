module ActiveJob
  module QueueAdapters
    class GoodJobAdapter < GoodJob::Adapter
      def initialize
        if Rails.env.development? || Rails.env.test?
          super(inline: true)
        else
          super(inline: false)
        end
      end
    end
  end
end
