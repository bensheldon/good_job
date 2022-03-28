# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::LogSubscriber do
  let(:subscriber) { described_class.new }

  around do |example|
    orig_loggers = described_class.loggers.dup
    described_class.loggers.clear
    described_class.reset_logger

    example.run

    described_class.loggers.replace(orig_loggers)
    described_class.reset_logger
  end

  describe "loggers" do
    let(:logs) { StringIO.new }

    it 'logs output with a simple logger' do
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect(logs.string).to include("GoodJob started scheduler with queues= max_threads=")
    end

    it 'logs output with a tagged logger with missing formatter' do
      logger = ActiveSupport::TaggedLogging.new(Logger.new(logs))
      logger.formatter = nil
      described_class.loggers << logger

      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect(logs.string).to include("GoodJob started scheduler with queues= max_threads=")
    end
  end
end
