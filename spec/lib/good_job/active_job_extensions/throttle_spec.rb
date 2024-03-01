# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Throttle do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'JOB_PERFORMED', Concurrent::AtomicBoolean.new(false)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Throttle

      def perform(name:)
        name && sleep(1)
        JOB_PERFORMED.make_true
      end
    end)
  end

  describe "when extension is only included but not configured" do
    it "does not throttle" do
      expect do
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline
      end.not_to raise_error
    end
  end

  describe "when throttle key returns nil" do
    it "does not throttle" do
      TestJob.good_job_throttle_with(
        count: 1,
        period: 1.minute,
        key: ->(job) {}
      )

      expect(TestJob.perform_later(name: "Alice")).to be_present
      expect(TestJob.perform_later(name: "Alice")).to be_present
    end
  end

  describe "when throttle key is nil" do
    it "does not throttle" do
      TestJob.good_job_throttle_with(
        count: 1,
        period: 1.minute,
        key: nil
      )

      expect(TestJob.perform_later(name: "Alice")).to be_present
      expect(TestJob.perform_later(name: "Alice")).to be_present
    end
  end

  describe ".good_job_throttle_with" do
    describe "count:", :skip_rails_5 do
      before do
        TestJob.good_job_throttle_with(
          count: 1,
          period: 1.minute,
          key: ->(job) { job.arguments.first[:name] }
        )
      end

      it "does not enqueue if limit is exceeded for a particular key" do
        expect(TestJob.new.perform(name: "Alice")).to be_present
        expect(TestJob.new.perform(name: "Alice")).to be false
      end
    end
  end

  describe "#good_job_throttle_key" do
    context "when retrying a job" do
      before do
        stub_const "TestJob", (Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Throttle

          good_job_throttle_with(
            count: 1,
            period: 1.minute,
            key: ->(job) { Time.current.to_f }
          )
          retry_on StandardError

          def perform(*)
            raise "ERROR"
          end
        end)
      end

      describe "retries" do
        it "preserves the value" do
          TestJob.set(wait_until: 5.minutes.ago).perform_later(name: "Alice")

          begin
            GoodJob.perform_inline
          rescue
            nil
          end

          expect(GoodJob::Execution.count).to eq 1
          expect(GoodJob::Execution.first.concurrency_key).to be_present
          expect(GoodJob::Job.first).not_to be_finished
        end

        context "when not discrete" do
          it "preserves the key value across retries" do
            TestJob.set(wait_until: 5.minutes.ago).perform_later(name: "Alice")
            GoodJob::Job.first.update!(is_discrete: false)

            begin
              GoodJob.perform_inline
            rescue
              nil
            end

            expect(GoodJob::Execution.count).to eq 2
            first_execution, retried_execution = GoodJob::Execution.order(created_at: :asc).to_a
            expect(retried_execution.concurrency_key).to eq first_execution.concurrency_key
          end
        end
      end
    end

    context "when no key is specified" do
      before do
        stub_const "TestJob", (Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Throttle

          def perform(name)
          end
        end)
      end

      it "uses the class name as the default throttle key" do
        job = TestJob.perform_later("Alice")
        expect(job.good_job_concurrency_key).to eq("TestJob")
      end
    end

    describe "#perform_later" do
      before do
        stub_const "TestJob", (Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Throttle

          good_job_throttle_with(
            count: 1,
            period: 1.minute,
            key: ->(job) { job.arguments.first }
          )

          def perform(arg)
          end
        end)
      end

      # it "raises an error for non-serializable types" do
      #   expect { TestJob.new.perform({key: "value"}) }.to raise_error(TypeError, "Throttle key must be a String; was a Hash")
      #   expect { TestJob.new.perform({key: "value"}.with_indifferent_access) }.to raise_error(TypeError)
      #   expect { TestJob.new.perform(["key"]) }.to raise_error(TypeError)
      #   expect { TestJob.new.perform(TestJob) }.to raise_error(TypeError)
      # end
    end
  end
end
