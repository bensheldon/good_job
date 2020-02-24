require 'rails_helper'

RSpec.describe GoodJob::Job do
  let(:job) { GoodJob::Job.create! }

  describe 'lockable' do
    describe '#advisory_lock' do
      it 'results in a locked record' do
        job.advisory_lock!
        expect(job.advisory_locked?).to be true
        expect(job.owns_advisory_lock?).to be true

        other_thread_owns_advisory_lock = Concurrent::Promises.future(job) { |j| j.owns_advisory_lock? }.value!
        expect(other_thread_owns_advisory_lock).to be false
      end
    end

    describe '#advisory_unlock' do
      it 'unlocks the record' do
        job.advisory_lock!

        expect do
          job.advisory_unlock
        end.to change(job, :advisory_locked?).from(true).to(false)
      end

      it 'unlocks the record only once' do
        job.advisory_lock!
        job.advisory_lock!

        expect do
          job.advisory_unlock
        end.not_to change(job, :advisory_locked?).from(true)
      end
    end

    describe '#advisory_unlock!' do
      it 'unlocks the record entirely' do
        job.advisory_lock!
        job.advisory_lock!

        expect do
          job.advisory_unlock!
        end.to change(job, :advisory_locked?).from(true).to(false)
      end

    end
  end

  it 'is lockable' do
    ActiveRecord::Base.clear_active_connections!
    job.advisory_lock!

    expect do
      Concurrent::Promises.future(job) { |j| j.advisory_lock! }.value!
    end.to raise_error GoodJob::Lockable::RecordAlreadyAdvisoryLockedError
  end
end
