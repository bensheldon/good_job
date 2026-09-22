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
  end

  describe "#enqueue_concurrency_limit_exceeded" do
    let(:logs) { StringIO.new }
    let(:job_class) { Class.new(ActiveJob::Base) { def self.name = "MyJob" } }
    let(:job) { job_class.new.tap { |j| j.job_id = "abc-123" } }

    it 'logs the aborted enqueue message' do
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { job: job, key: "mykey", limit: 5 })

      subscriber.enqueue_concurrency_limit_exceeded(event)
      expect(logs.string).to include("Aborted enqueue of MyJob (Job ID: abc-123) because the concurrency key 'mykey' has reached its enqueue limit of 5 jobs")
    end

    it 'pluralizes the message for a single job' do
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { job: job, key: "mykey", limit: 1 })

      subscriber.enqueue_concurrency_limit_exceeded(event)
      expect(logs.string).to include("has reached its enqueue limit of 1 job")
    end
  end

  describe "#enqueue_concurrency_throttle_exceeded" do
    let(:logs) { StringIO.new }
    let(:job_class) { Class.new(ActiveJob::Base) { def self.name = "MyJob" } }
    let(:job) { job_class.new.tap { |j| j.job_id = "abc-123" } }

    it 'logs the aborted enqueue message' do
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { job: job, key: "mykey", limit: 5 })

      subscriber.enqueue_concurrency_throttle_exceeded(event)
      expect(logs.string).to include("Aborted enqueue of MyJob (Job ID: abc-123) because the concurrency key 'mykey' has reached its throttle limit of 5 jobs")
    end
  end

  describe "#cluster_reap" do
    let(:logs) { StringIO.new }

    before { described_class.loggers << Logger.new(logs) }

    it 'logs the exit status of a subprocess that exited on its own' do
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { pid: 123, status: 1, signal: nil })

      subscriber.cluster_reap(event)
      expect(logs.string).to include("reaped subprocess (PID: 123, exit status: 1)")
    end

    it 'logs the signal name of a subprocess that was signaled' do
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { pid: 123, status: nil, signal: 9 })

      subscriber.cluster_reap(event)
      expect(logs.string).to include("reaped subprocess (PID: 123, signal: KILL)")
    end
  end

  describe "#cluster_backoff" do
    let(:logs) { StringIO.new }

    it 'warns about the delayed replacement of a repeatedly exiting subprocess' do
      described_class.loggers << Logger.new(logs)
      event = ActiveSupport::Notifications::Event.new("", nil, nil, "id", { restart_count: 3, delay: 2 })

      subscriber.cluster_backoff(event)
      expect(logs.string).to include("delaying the replacement of a repeatedly exiting subprocess by 2 seconds (consecutive unhealthy exits: 3)")
    end
  end
end
