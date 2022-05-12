# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::CleanupTracker do
  describe '#cleanup?' do
    context 'with default parameters' do
      it 'will never trigger a cleanup' do
        tracker = described_class.new

        1000.times { tracker.increment }
        travel_to 1.year.from_now do
          expect(tracker.cleanup?).to be false
        end
      end
    end

    it 'will trigger a after cleanup_interval_jobs is exceeded' do
      tracker = described_class.new(cleanup_interval_seconds: nil, cleanup_interval_jobs: 10)

      10.times { tracker.increment }
      expect(tracker.cleanup?).to be false

      tracker.increment
      expect(tracker.cleanup?).to be true
    end
  end

  describe '#increment' do
    it 'increments cleanup_count' do
      tracker = described_class.new

      expect { tracker.increment }.to change(tracker, :job_count).by(1)
    end
  end

  describe '#reset' do
    it 'resets job_count and last_at' do
      tracker = described_class.new

      1000.times { tracker.increment }
      travel_to 1.year.from_now do
        tracker.reset

        expect(tracker.job_count).to eq 0
        expect(tracker.last_at).to be_within(0.1).of(Time.current)
      end
    end
  end
end
