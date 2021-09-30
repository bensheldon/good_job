# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::CurrentThread do
  [
    :cron_key,
    :execution,
    :error_on_discard,
    :error_on_retry,
  ].each do |accessor|
    describe ".#{accessor}" do
      it 'maintains value across threads' do
        described_class.send "#{accessor}=", 'apple'

        Thread.new do
          described_class.send "#{accessor}=", 'bear'
        end.join

        expect(described_class.send(accessor)).to eq 'apple'
      end

      it 'maintains value across Rails reloader wrapper' do
        Rails.application.reloader.wrap do
          described_class.send "#{accessor}=", 'apple'
        end

        expect(described_class.send(accessor)).to eq 'apple'
      end

      it 'is resettable' do
        described_class.send "#{accessor}=", 'apple'
        described_class.reset
        expect(described_class.send(accessor)).to eq nil
      end
    end
  end

  describe '.active_job_id' do
    let!(:execution) { GoodJob::Execution.create! active_job_id: SecureRandom.uuid }

    it 'delegates to good_job' do
      expect(described_class.active_job_id).to be_nil

      described_class.execution = execution
      expect(described_class.active_job_id).to eq execution.active_job_id
    end
  end
end
