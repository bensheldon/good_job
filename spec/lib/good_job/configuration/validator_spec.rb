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
      expect(configuration.errors[:cron]).to include(/invalid/)
    end
  end
end
