# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Manager do
  let(:configuration) { GoodJob::Configuration.new({}) }
  let(:manager) { described_class.new(configuration: configuration) }

  after do
    manager.shutdown
  end

  describe '#create_thread' do
    let(:scheduler) { instance_double(GoodJob::Scheduler, create_thread: nil, shutdown: nil) }

    before do
      allow(GoodJob::Scheduler).to receive(:from_configuration).and_return(scheduler)
    end

    it "instantiates a scheduler once and calls Scheduler#create_thread" do
      state = { queue_name: 'mice' }
      manager.create_thread(state)
      manager.create_thread(state)
      expect(GoodJob::Scheduler).to have_received(:from_configuration).once
      expect(scheduler).to have_received(:create_thread).with(state).twice
    end
  end
end
