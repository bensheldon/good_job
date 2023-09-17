module GoodJob
  module Middleware
    class CatchAll
      def self.call(env)
        [404, {}, ["Not found"]]
      end
    end
  end
end
