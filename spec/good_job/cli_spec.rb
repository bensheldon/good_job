# frozen_string_literal: true
require 'rails_helper'
require 'good_job/cli'

RSpec.describe GoodJob::CLI do
  before do
    stub_const 'GoodJob::CLI::RAILS_ENVIRONMENT_RB', File.expand_path("spec/dummy/config/environment.rb")
  end

  describe '#start' do
    it 'initializes a scheduler' do
      scheduler_mock = instance_double GoodJob::Scheduler
      allow(GoodJob::Scheduler).to receive(:new).and_return scheduler_mock
      allow(Kernel).to receive(:loop)

      cli = described_class.new([], {}, {})
      cli.start

      expect(GoodJob::Scheduler).to have_received(:new)
    end
  end
end
