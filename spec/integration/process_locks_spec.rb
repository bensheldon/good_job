# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Process Locks' do
  let(:capsule) { GoodJob::Capsule.new }
  let(:inline_adapter) { GoodJob::Adapter.new(execution_mode: :inline, _capsule: capsule) }
  let(:async_adapter) { GoodJob::Adapter.new(execution_mode: :async, _capsule: capsule) }

  before do
    capsule.start

    stub_const("PROCESS_IDS", Concurrent::Array.new)
    stub_const "TestJob", (Class.new(ActiveJob::Base) do
      def perform
        PROCESS_IDS << GoodJob::Job.where(id: provider_job_id).pick(:locked_by_id)
      end
    end)
  end

  after do
    capsule.shutdown
  end

  it 'stores process_id in inline job' do
    TestJob.queue_adapter = inline_adapter
    TestJob.perform_later

    wait_until { expect(GoodJob::Job.last.finished_at).to be_present }
    expect(PROCESS_IDS.size).to eq 1
    expect(PROCESS_IDS.first).to be_a_uuid
    expect(PROCESS_IDS.first).to eq capsule.process_id
    expect(GoodJob::Job.last.locked_by_id).to be_nil
  end

  it 'stores process_id in async job' do
    TestJob.queue_adapter = async_adapter
    TestJob.perform_later

    wait_until { expect(GoodJob::Job.pick(:finished_at)).to be_present }
    expect(PROCESS_IDS.size).to eq 1
    expect(PROCESS_IDS.first).to be_a_uuid
    expect(PROCESS_IDS.first).to eq capsule.process_id
    expect(GoodJob::Job.last.locked_by_id).to be_nil
  end
end
