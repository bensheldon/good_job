# frozen_string_literal: true

module GoodJob
  class ProbeServer
    module Middleware
      class Catchall
        def call(_)
          [404, {}, ["Not found"]]
        end
      end
    end
  end
end
