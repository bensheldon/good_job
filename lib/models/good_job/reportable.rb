# frozen_string_literal: true
module GoodJob
  module Reportable
    # The last relevant timestamp for this execution
    def last_status_at
      finished_at || performed_at || scheduled_at || created_at
    end
  end
end
