# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Configuration::Validator do
  before do
    stub_const 'TestJob', Class.new(ActiveJob::Base)
  end

  describe '#valid?' do
    it 'is valid when there is no cron configuration' do
      configuration = GoodJob::Configuration.new({})
      expect(configuration).to be_valid
    end

    it 'is valid when cron job classes exist' do
      cron = { test: { cron: "* * * * *", class: "TestJob" } }
      configuration = GoodJob::Configuration.new({ cron: cron })
      expect(configuration).to be_valid
    end

    it 'is valid when the cron job class is a Class' do
      cron = { test: { cron: "* * * * *", class: TestJob } }
      configuration = GoodJob::Configuration.new({ cron: cron })
      expect(configuration).to be_valid
    end

    it 'is valid when the cron job class is a callable' do
      cron = { test: { cron: "* * * * *", class: -> { "TestJob" } } }
      configuration = GoodJob::Configuration.new({ cron: cron })
      expect(configuration).to be_valid
    end

    it 'is valid when priority is ignored with the scheduled_at dequeue sort' do
      configuration = GoodJob::Configuration.new({ dequeue_query_sort: :scheduled_at, dequeue_query_priority: false })
      expect(configuration).to be_valid
    end

    it 'is invalid when priority is ignored with the created_at dequeue sort' do
      configuration = GoodJob::Configuration.new({ dequeue_query_sort: :created_at, dequeue_query_priority: false })

      expect(configuration).not_to be_valid
      expect(configuration.errors[:dequeue_query_priority]).to include(/dequeue_query_sort is :scheduled_at/)
    end

    it 'is invalid when a cron job class does not exist' do
      cron = { test: { cron: "* * * * *", class: "NonexistentJob" } }
      configuration = GoodJob::Configuration.new({ cron: cron })

      expect(configuration).not_to be_valid
      expect(configuration.errors[:cron]).to include(/NonexistentJob/)
    end

    it 'is invalid when a cron expression does not parse' do
      cron = { test: { cron: "2017-12-12", class: "TestJob" } }
      configuration = GoodJob::Configuration.new({ cron: cron })

      expect(configuration).not_to be_valid
      expect(configuration.errors[:cron]).to include(/not a valid schedule/)
    end
  end
end
