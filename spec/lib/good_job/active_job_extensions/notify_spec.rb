# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Notify do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    allow(GoodJob::Notifier).to receive(:notify)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Notify

      def perform
      end
    end)
  end

  it 'notifies by default' do
    TestJob.perform_later
    expect(GoodJob::Notifier).to have_received(:notify)
  end

  it 'does not notify when good_job_notify is false' do
    TestJob.set(good_job_notify: false).perform_later
    expect(GoodJob::Notifier).not_to have_received(:notify)
  end
end
