# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ProcessesController do
  it 'renders process capacity with or without fiber stats' do
    GoodJob::Process.create!(state: GoodJob::Process.process_state.merge(schedulers: [
                                                                           { queues: 'legacy', max_threads: 5 },
                                                                           { queues: 'io', max_threads: 1, max_fibers: 25 },
                                                                         ]))

    get good_job.processes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('queues=legacy max_threads=5', 'queues=io max_threads=1 max_fibers=25')
  end
end
