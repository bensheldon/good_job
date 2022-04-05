# frozen_string_literal: true
module GoodJob
  class ProcessesController < GoodJob::ApplicationController
    def index
      @processes = GoodJob::Process.active.order(created_at: :desc) if GoodJob::Process.migrated?
    end
  end
end
