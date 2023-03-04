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
      expect(logs.string).to include("GoodJob #{GoodJob::VERSION} started scheduler with queues= max_threads=")
    end

    it 'logs output with a tagged logger with missing formatter' do
      logger = ActiveSupport::TaggedLogging.new(Logger.new(logs))
      logger.formatter = nil
      described_class.loggers << logger

      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect(logs.string).to include("GoodJob #{GoodJob::VERSION} started scheduler with queues= max_threads=")
    end

    it 'flushes stdout if writing to stdout and sync is false' do
      allow($stdout).to receive(:flush)
      allow($stdout).to receive(:sync).and_return(false)
      described_class.loggers << Logger.new($stdout)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect($stdout).to have_received(:flush)
    end

    it 'does not flush stdout if not writing to stdout' do
      allow($stdout).to receive(:flush)
      allow($stdout).to receive(:sync).and_return(false)
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect($stdout).not_to have_received(:flush)
    end

    it 'does not flush stdout if writing to stdout and sync is true' do
      allow($stdout).to receive(:flush)
      allow($stdout).to receive(:sync).and_return(true)
      described_class.loggers << Logger.new($stdout)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", {})

      subscriber.scheduler_create_pool(event)
      expect($stdout).not_to have_received(:flush)
    end
  end

  describe ".logging_to_stdout?" do
    it "returns true if logger attached to LogSubscriber writes to STDOUT" do
      described_class.loggers << Logger.new($stdout)

      expect(described_class.logging_to_stdout?).to be(true)
    end

    it "returns false if logger attached to LogSubscriber does not write to STDOUT" do
      described_class.loggers << Logger.new(StringIO.new)

      expect(described_class.logging_to_stdout?).to be(false)
    end
  end
end
