# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::AdvisoryLockable do
  before do
    stub_const "TestRecord", (Class.new(GoodJob::BaseRecord) do
      include GoodJob::AdvisoryLockable
      self.table_name = "good_jobs"
      self.advisory_lockable_column = "active_job_id"
    end)
  end

  let(:model_class) { TestRecord }
  let!(:job) { model_class.create!(active_job_id: SecureRandom.uuid, queue_name: "default") }
  let!(:another_job) { model_class.create!(active_job_id: SecureRandom.uuid, queue_name: "default") }

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

    it 'generates bind parameters' do
      query = model_class.where(priority: 99).order(priority: :desc).limit(2).advisory_lock
      _sql, binds, _preparable = model_class.connection.send :to_sql_and_binds, query.arel
      expect(binds.size).to eq 2 # priority and limit
    end

    it 'is preparable', skip: !defined?(Arel::Nodes::BoundSqlLiteral) do
      query = model_class.where(priority: 99).order(priority: :desc).limit(2).advisory_lock
      _sql, _binds, preparable = model_class.connection.send :to_sql_and_binds, query.arel
      expect(preparable).to eq true
    end

    describe 'lockable column do' do
      it 'default column generates appropriate SQL' do
        allow(model_class).to receive(:advisory_lockable_column).and_return(:id)

        query = model_class.where(priority: 99).order(priority: :desc).limit(2).advisory_lock
        expect(normalize_sql(query.to_sql)).to eq normalize_sql(<<~SQL.squish)
          SELECT "good_jobs".*
          FROM "good_jobs"
          WHERE "good_jobs"."id" IN (
            WITH "rows" AS #{'MATERIALIZED' if model_class.supports_cte_materialization_specifiers?} (
              SELECT "good_jobs"."id", "good_jobs"."id"
              FROM "good_jobs"
              WHERE "good_jobs"."priority" = 99
              ORDER BY "good_jobs"."priority" DESC
            )
            SELECT "rows"."id"
            FROM "rows"
            WHERE pg_try_advisory_lock(('x' || substr(md5('good_jobs' || '-' || "rows"."id"::text), 1, 16))::bit(64)::bigint)
            LIMIT 2
          )
          ORDER BY "good_jobs"."priority" DESC
        SQL
      end

      it 'can be customized with `lockable_column`' do
        allow(model_class).to receive(:advisory_lockable_column).and_return("queue_name")
        query = model_class.order(priority: :desc).limit(2).advisory_lock

        expect(normalize_sql(query.to_sql)).to eq normalize_sql(<<~SQL.squish)
          SELECT "good_jobs".*
          FROM "good_jobs"
          WHERE "good_jobs"."id" IN (
            WITH "rows" AS #{'MATERIALIZED' if model_class.supports_cte_materialization_specifiers?} (
              SELECT "good_jobs"."id", "good_jobs"."queue_name"
              FROM "good_jobs"
              ORDER BY "good_jobs"."priority" DESC
            )
            SELECT "rows"."id"
            FROM "rows"
            WHERE pg_try_advisory_lock(('x' || substr(md5('good_jobs' || '-' || "rows"."queue_name"::text), 1, 16))::bit(64)::bigint)
            LIMIT 2
          )
          ORDER BY "good_jobs"."priority" DESC
        SQL
      end
    end

    describe 'select limit' do
      it 'introduces a limit into the materialized CTE' do
        query = model_class.advisory_lock(select_limit: 1000)
        expect(normalize_sql(query.to_sql)).to eq normalize_sql(<<~SQL.squish)
          SELECT "good_jobs".*
          FROM "good_jobs"
          WHERE "good_jobs"."id" IN (
            WITH "rows" AS #{'MATERIALIZED' if model_class.supports_cte_materialization_specifiers?} (
              SELECT "good_jobs"."id", "good_jobs"."active_job_id"
              FROM "good_jobs"
              LIMIT 1000
            )
            SELECT "rows"."id"
            FROM "rows"
            WHERE pg_try_advisory_lock(('x' || substr(md5('good_jobs' || '-' || "rows"."active_job_id"::text), 1, 16))::bit(64)::bigint)
          )
        SQL
      end
    end

    it 'returns first row of the query with a lock' do
      job.update!(queue_name: "aaaaaa")
      another_job.update!(queue_name: "bbbbbb")

      expect(job).not_to be_advisory_locked
      result_job = model_class.order(queue_name: :asc).limit(1).advisory_lock.first
      expect(result_job).to eq job
      expect(job).to be_advisory_locked
      expect(another_job).not_to be_advisory_locked

      job.advisory_unlock
    end

    it 'can lock an alternative column' do
      expect(job).not_to be_advisory_locked
      result_job = model_class.order(created_at: :asc).limit(1).advisory_lock(column: :queue_name).first
      expect(result_job).to eq job
      expect(job).to be_advisory_locked(key: "good_jobs-default")
      expect(job).not_to be_advisory_locked # on default key

      job.advisory_unlock(key: "good_jobs-default")
    end
  end

  describe '.advisory_lock_key' do
    it 'locks a key' do
      model_class.advisory_lock_key(job.lockable_key)
      expect(job).to be_advisory_locked
      expect(model_class.advisory_locked_key?(job.lockable_key)).to be true
      model_class.advisory_unlock_key(job.lockable_key)
    end

    context 'when a block is passed' do
      it 'locks that key for the bloc and then unlocks it' do
        model_class.advisory_lock_key(job.lockable_key) do
          expect(job.advisory_locked?).to be true
          expect(job.owns_advisory_lock?).to be true
          expect(PgLock.current_database.advisory_lock.count).to eq 1
        end

        expect(job.advisory_locked?).to be false
        expect(job.owns_advisory_lock?).to be false
      end

      it 'does not invoke the block if the key is already locked' do
        model_class.advisory_lock_key(job.lockable_key) do
          promise = rails_promise do
            result = model_class.advisory_lock_key(job.lockable_key) { raise }
            expect(result).to be_nil
          end
          expect { promise.value! }.not_to raise_error
        end
      end
    end
  end

  describe '.advisory_locked_key?' do
    it 'tests whether the key is locked' do
      key = SecureRandom.uuid
      expect(model_class.advisory_locked_key?(key)).to eq false

      model_class.advisory_lock_key(key)
      expect(model_class.advisory_locked_key?(key)).to eq true

      model_class.advisory_unlock_key(key)
      expect(model_class.advisory_locked_key?(key)).to eq false
    end
  end

  describe '.owns_advisory_lock_key?' do
    it 'tests whether the key is locked' do
      locked_event = Concurrent::Event.new
      done_event = Concurrent::Event.new

      promise = rails_promise do
        model_class.advisory_lock_key(job.lockable_key) do
          expect(job.owns_advisory_lock?).to be true

          locked_event.set
          done_event.wait(5)
        end
      end

      locked_event.wait(5)
      expect(job.owns_advisory_lock?).to be false
    ensure
      locked_event.set
      done_event.set
      promise.value!
    end
  end

  describe '.with_advisory_lock' do
    it 'opens a block with a lock that locks and unlocks records' do
      records = nil
      model_class.limit(2).with_advisory_lock do |results|
        records = results

        expect(records).to include(job)
        expect(records).to all be_advisory_locked
      end

      expect(records).to all be_advisory_unlocked
      expect(PgLock.current_database.advisory_lock.count).to eq 0
    end

    it 'can unlock all advisory locks on the session with `unlock_session: true`' do
      another_record = model_class.create(create_with_advisory_lock: true)

      model_class.where.not(id: another_record.id)
                 .with_advisory_lock(unlock_session: true) { |_records| nil }

      expect(another_record).not_to be_advisory_locked
      expect(PgLock.current_database.advisory_lock.count).to eq 0
    end

    it 'does not leak relation scope into inner queries' do
      sql = model_class.where(finished_at: nil).limit(1).with_advisory_lock do |_results|
        model_class.all.to_sql
      end

      expect(sql).to eq 'SELECT "good_jobs".* FROM "good_jobs"'
    end

    it 'aborts save if cannot be advisory locked' do
      uuid = SecureRandom.uuid
      locked_event = Concurrent::Event.new
      done_event = Concurrent::Event.new

      promise = rails_promise do
        model_class.advisory_lock_key("good_jobs-#{uuid}") do
          locked_event.set
          done_event.wait(5)
        end
      end

      locked_event.wait(5)
      record = model_class.create(id: uuid, active_job_id: uuid, create_with_advisory_lock: true)
      expect(record).not_to be_persisted
      expect(record.errors[:active_job_id]).to include("Failed to acquire advisory lock: good_jobs-#{uuid}")

      expect { model_class.create!(id: uuid, active_job_id: uuid, create_with_advisory_lock: true) }.to raise_error ActiveRecord::RecordInvalid
    ensure
      done_event.set
      promise.value!
    end
  end

  describe '.includes_advisory_locks' do
    it 'includes the locktable data' do
      job.advisory_lock!

      record = model_class.where(id: job.id).includes_advisory_locks.first
      expect(record['locktype']).to eq "advisory"
      expect(record['owns_advisory_lock']).to be true

      job.advisory_unlock
    end
  end

  describe '#advisory_lock' do
    it 'results in a locked record' do
      job.advisory_lock!
      expect(job.advisory_locked?).to be true
      expect(job.owns_advisory_lock?).to be true

      other_thread_owns_advisory_lock = rails_promise(job, &:owns_advisory_lock?).value!
      expect(other_thread_owns_advisory_lock).to be false

      job.advisory_unlock
    end

    it 'returns true or false if the lock is acquired' do
      expect(job.advisory_lock).to be true

      expect(rails_promise(job, &:advisory_lock).value!).to be false

      job.advisory_unlock
    end

    it 'can lock alternative values' do
      job.advisory_lock!(key: "alternative")
      expect(job.advisory_locked?(key: "alternative")).to be true
      expect(job.advisory_locked?).to be false

      job.advisory_unlock(key: "alternative")
    end

    it 'can lock alternative postgres functions' do
      job.advisory_lock!(function: "pg_advisory_lock")
      expect(job.advisory_locked?).to be true
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

    it 'returns true or false if the unlock operation is successful' do
      job.advisory_lock

      expect(rails_promise(job, &:advisory_unlock).value!).to be false
      expect(job.advisory_unlock).to be true

      unless RUBY_PLATFORM.include?('java')
        expect(POSTGRES_NOTICES.first).to include "you don't own a lock of type ExclusiveLock"
        POSTGRES_NOTICES.clear
      end
    end
  end

  describe '#advisory_locked?' do
    it 'reflects whether the record is locked' do
      expect(job.advisory_locked?).to be false
      job.advisory_lock
      expect(job.advisory_locked?).to be true
      job.advisory_unlock
      expect(job.advisory_locked?).to be false
    end

    it 'is accurate even if the job has been destroyed' do
      job.advisory_lock
      expect(job.advisory_locked?).to be true
      job.destroy!
      expect(job.advisory_locked?).to be true
      job.advisory_unlock
      expect(job.advisory_locked?).to be false
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

  describe '.advisory_unlock_session' do
    it 'unlocks all locks in the session' do
      job.advisory_lock!

      model_class.advisory_unlock_session

      expect(job.advisory_locked?).to be false
    end
  end

  describe 'create_with_advisory_lock' do
    it 'causes the job to be saved and locked' do
      job = model_class.new
      job.create_with_advisory_lock = true
      job.save!

      expect(job).to be_advisory_locked

      job.advisory_unlock
    end

    it 'aborts when the lock already exists' do
      existing = model_class.create!(active_job_id: SecureRandom.uuid, create_with_advisory_lock: true)

      expect do
        rails_promise { model_class.create!(active_job_id: existing.active_job_id, create_with_advisory_lock: true) }.value!
      end.to raise_error(ActiveRecord::RecordInvalid)
    ensure
      existing.advisory_unlock
    end
  end

  it 'is lockable' do
    ActiveRecord::Base.connection_handler.clear_active_connections!
    job.advisory_lock!

    expect do
      rails_promise(job, &:advisory_lock!).value!
    end.to raise_error GoodJob::AdvisoryLockable::RecordAlreadyAdvisoryLockedError

    job.advisory_unlock
  end

  describe 'Advisory Lock behavior' do
    it 'connection-level locks lock immediately within transactions' do
      locked_event = Concurrent::Event.new
      commit_event = Concurrent::Event.new
      committed_event = Concurrent::Event.new
      done_event = Concurrent::Event.new

      promise = rails_promise do
        job.class.connection # <= This is necessary to fixate the connection in the thread

        job.class.transaction do
          job.advisory_lock
          locked_event.set

          commit_event.wait(10)
        end
        committed_event.set

        done_event.wait(10)
        job.advisory_unlock
      end

      locked_event.wait(10)
      expect(job.advisory_locked?).to be true
      commit_event.set

      committed_event.wait(10)
      expect(job.advisory_locked?).to be true

      done_event.set
      promise.value!
    end

    it 'transaction-level locks only lock within transactions' do
      locked_event = Concurrent::Event.new
      commit_event = Concurrent::Event.new
      committed_event = Concurrent::Event.new
      done_event = Concurrent::Event.new

      promise = rails_promise do
        job.class.transaction do
          job.advisory_lock(function: "pg_advisory_xact_lock")
          locked_event.set

          commit_event.wait(10)
        end
        committed_event.set

        done_event.wait(10)
      end

      locked_event.wait(10)
      expect(job.advisory_locked?).to be true
      commit_event.set

      committed_event.wait(10)
      expect(job.advisory_locked?).to be false

      done_event.set
      promise.value!
    end
  end
end
