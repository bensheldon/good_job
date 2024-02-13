# frozen_string_literal: true

module GoodJob
  class ProbeServer
    module NotFoundApp
      def self.call(_env)
        [404, {}, ["Not found"]]
      end
    end
  end
end
