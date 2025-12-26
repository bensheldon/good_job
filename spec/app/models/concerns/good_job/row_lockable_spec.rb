# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::RowLockable do
  before do
    stub_const "TestRecord", (Class.new(GoodJob::BaseRecord) do
      include GoodJob::RowLockable
      include GoodJob::AdvisoryLockable

      self.table_name = "good_jobs"
    end)
  end

  let(:model_class) { TestRecord }
  let!(:job) { model_class.create!(active_job_id: SecureRandom.uuid, queue_name: "default") }
  let!(:another_job) { model_class.create!(active_job_id: SecureRandom.uuid, queue_name: "default") }

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

  describe '.row_lock' do
    it 'returns the locked record' do
      locked_by_id = SecureRandom.uuid

      locked_job = model_class.where(id: job.id).row_lock(locked_by_id: locked_by_id).first
      expect(locked_job).to eq(job)
      expect(locked_job.locked_by_id).to eq(locked_by_id)
      expect(locked_job.locked_at).to be_present
    end

    it 'returns nil if no records are locked' do
      locked_job = model_class.where(id: nil).row_lock(locked_by_id: SecureRandom.uuid)
      expect(locked_job).to be_empty
    end

    it "respects the limit" do
      locked_job = model_class.limit(2).row_lock(locked_by_id: SecureRandom.uuid)
      expect(locked_job.to_a).to contain_exactly(job, another_job)
    end
  end

  it "generates the appropriate SQL" do
    connection = model_class.connection
    allow(connection).to receive(:exec_query).and_call_original
    allow(model_class).to receive(:connection).and_return(connection)

    locked_by_id = SecureRandom.uuid

    model_class.where(id: job.id).order(id: :asc).row_lock(locked_by_id: locked_by_id)

    expect(connection).to have_received(:exec_query) do |sql, _name, _binds|
      expect(normalize_sql(sql)).to eq normalize_sql(<<~SQL.squish)
        UPDATE "good_jobs"
        SET "locked_at" = $1, "locked_by_id" = $2
        WHERE "good_jobs"."id" IN (
          SELECT "good_jobs"."id"
          FROM "good_jobs"
          WHERE "good_jobs"."id" = $3
          ORDER BY "good_jobs"."id" ASC
          FOR NO KEY UPDATE SKIP LOCKED
        )
        RETURNING *
      SQL
    end
  end
end
