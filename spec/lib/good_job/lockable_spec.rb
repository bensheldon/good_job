require 'rails_helper'

RSpec.describe GoodJob::Lockable do
  let(:model_class) { GoodJob::Job }
  let(:job) { model_class.create! }

  describe '.advisory_lock' do
    around do |example|
      RSpec.configure do |config|
        config.expect_with :rspec do |c|
          original_max_formatted_output_length = c.instance_variable_get(:@max_formatted_output_length)

          c.max_formatted_output_length = 1000000
          example.run

          c.max_formatted_output_length = original_max_formatted_output_length
        end
      end
    end

    it 'generates appropriate SQL' do
      query = model_class.where(priority: 99).order(priority: :desc).limit(2).advisory_lock

      expect(normalize_sql(query.to_sql)).to eq normalize_sql(<<~SQL.squish)
        SELECT "good_jobs".*
        FROM "good_jobs"
        WHERE "good_jobs"."id" IN (
          WITH "rows" AS #{'MATERIALIZED' if model_class.supports_cte_materialization_specifiers?} (
            SELECT "good_jobs"."id"
            FROM "good_jobs"
            WHERE "good_jobs"."priority" = 99
            ORDER BY "good_jobs"."priority" DESC
          )
          SELECT "rows"."id"
          FROM "rows"
          WHERE pg_try_advisory_lock(('x' || substr(md5('good_jobs' || "rows"."id"::text), 1, 16))::bit(64)::bigint)
          LIMIT 2
        )
        ORDER BY "good_jobs"."priority" DESC
      SQL
    end

    it 'returns first row of the query with a lock' do
      expect(job).not_to be_advisory_locked
      result_job = model_class.advisory_lock.first
      expect(result_job).to eq job
      expect(job).to be_advisory_locked

      job.advisory_unlock
    end
  end

  describe '.with_advisory_lock' do
    it 'opens a block with a lock' do
      records = nil
      model_class.limit(2).with_advisory_lock do |results|
        records = results
        expect(records).to all be_advisory_locked
      end

      expect(records).to all be_advisory_unlocked
      expect(PgLock.advisory_lock.count).to eq 0
    end

    it 'does not leak advisory locks' do
      model_class.limit(2).with_advisory_lock do |results|
        records = results
        expect(records).to all be_advisory_locked
      end
    end
  end

  describe '#advisory_lock' do
    it 'results in a locked record' do
      job.advisory_lock!
      expect(job.advisory_locked?).to be true
      expect(job.owns_advisory_lock?).to be true

      other_thread_owns_advisory_lock = Concurrent::Promises.future(job, &:owns_advisory_lock?).value!
      expect(other_thread_owns_advisory_lock).to be false

      job.advisory_unlock
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

      job.advisory_unlock
    end

    it 'unlocks the record even after the record is destroyed' do
      job.advisory_lock!
      job.destroy!

      expect do
        job.advisory_unlock
      end.to change(job, :advisory_locked?).from(true).to(false)
    end
  end

  describe '#advisory_locked?' do
    it 'reflects whether the record is locked' do
      expect(job.advisory_locked?).to eq false
      job.advisory_lock
      expect(job.advisory_locked?).to eq true
      job.advisory_unlock
      expect(job.advisory_locked?).to eq false
    end

    it 'is accurate even if the job has been destroyed' do
      job.advisory_lock
      expect(job.advisory_locked?).to eq true
      job.destroy!
      expect(job.advisory_locked?).to eq true
      job.advisory_unlock
      expect(job.advisory_locked?).to eq false
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

  describe 'create_with_lock' do
    it 'causes the job to be saved and locked' do
      job = model_class.new
      job.create_with_advisory_lock = true
      job.save!

      expect(job).to be_advisory_locked

      job.advisory_unlock
    end
  end

  it 'is lockable' do
    ActiveRecord::Base.clear_active_connections!
    job.advisory_lock!

    expect do
      Concurrent::Promises.future(job, &:advisory_lock!).value!
    end.to raise_error GoodJob::Lockable::RecordAlreadyAdvisoryLockedError

    job.advisory_unlock
  end
end
