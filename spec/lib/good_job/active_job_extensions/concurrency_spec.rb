# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Concurrency do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'JOB_PERFORMED', Concurrent::AtomicBoolean.new(false)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency

      def perform(name:)
        name && sleep(1)
        JOB_PERFORMED.make_true
      end
    end)
  end

  describe 'when extension is only included but not configured' do
    it 'does not limit concurrency' do
      expect do
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline
      end.not_to raise_error
    end
  end

  describe 'label and key deprecation' do
    before do
      allow(GoodJob.deprecator).to receive(:warn)
    end

    it 'warns when a label rule declares a custom key' do
      TestJob.good_job_concurrency_rule(label: 'email', key: 'custom', perform_limit: 1)
      2.times do
        TestJob.set(good_job_labels: 'email').perform_later(name: nil)
        GoodJob.perform_inline
      end

      expect(GoodJob.deprecator).to have_received(:warn).with(/Supplying both `label:` and `key:`.*Remove `key:`/).once
    end

    it 'warns when a rule declares dynamic labels and keys' do
      TestJob.good_job_concurrency_rule(label: -> { 'email' }, key: -> { 'custom' }, perform_limit: 1)

      expect(GoodJob.deprecator).to have_received(:warn).once
    end

    it 'does not warn for label-only rules or blank custom keys' do
      TestJob.good_job_concurrency_rule(label: 'email', perform_limit: 1)
      TestJob.good_job_concurrency_rule(label: 'email', key: nil, perform_limit: 1)
      TestJob.good_job_concurrency_rule(label: 'email', key: '', perform_limit: 1)

      expect(GoodJob.deprecator).not_to have_received(:warn)
    end

    it 'does not warn for key-only rules or legacy key configuration' do
      TestJob.good_job_concurrency_rule(key: 'custom', perform_limit: 1)
      TestJob.good_job_control_concurrency_with(key: 'custom', perform_limit: 1)
      TestJob.perform_later(name: nil)
      GoodJob.perform_inline

      expect(GoodJob.deprecator).not_to have_received(:warn)
    end
  end

  describe '.good_job_control_concurrency_with' do
    describe 'total_limit:' do
      before do
        TestJob.good_job_concurrency_rule(
          label: "testlabel",
          total_limit: -> { 1 }
        )
      end

      it "does not enqueue if limit is exceeded for a particular key" do
        expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present
        expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be false
      end

      it "is inclusive of both performing and enqueued jobs" do
        expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present

        Rails.application.executor.wrap do
          GoodJob::Job.all.with_advisory_lock do
            expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be false
          end
        end
      end
    end

    describe 'enqueue_limit:' do
      before do
        TestJob.good_job_concurrency_rule(
          enqueue_limit: -> { 2 },
          label: "testlabel"
        )
      end

      it "does not enqueue if enqueue concurrency limit is exceeded for a particular key" do
        abort_events = []
        enqueue_events = []
        enqueue_callback = ->(*args) { enqueue_events << ActiveSupport::Notifications::Event.new(*args) }
        abort_callback = ->(*args) { abort_events << ActiveSupport::Notifications::Event.new(*args) }

        ActiveSupport::Notifications.subscribed(enqueue_callback, "enqueue.active_job") do
          ActiveSupport::Notifications.subscribed(abort_callback, "enqueue_concurrency_limit_exceeded.good_job") do
            expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present
            expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present

            # Third usage of key does not enqueue
            expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be false

            # Usage of different key does enqueue
            expect(TestJob.set(good_job_labels: "otherlabel").perform_later(name: "Bob")).to be_present
          end
        end

        expect(GoodJob::Job.labeled("testlabel").count).to eq 2
        expect(GoodJob::Job.labeled("otherlabel").count).to eq 1

        expect(abort_events.size).to eq 1
        expect(abort_events.first.payload).to include(key: 'label:testlabel', limit: 2)
        expect(abort_events.first.payload[:job]).to be_a(TestJob)

        # Aborted enqueues must not be logged as successfully enqueued (regression: PR #820).
        successful = enqueue_events.reject { |e| e.payload[:aborted] }
        expect(successful.count { |e| e.payload[:job].arguments == [{ name: "Alice" }] }).to eq 2
        expect(successful.count { |e| e.payload[:job].arguments == [{ name: "Bob" }] }).to eq 1
      end

      it 'excludes jobs that are already executing/locked' do
        expect(TestJob.perform_later(name: "Alice")).to be_present
        expect(TestJob.perform_later(name: "Alice")).to be_present

        # Lock one of the jobs
        Rails.application.executor.wrap do
          GoodJob::Job.first.with_advisory_lock do
            # Third usage does enqueue
            expect(TestJob.perform_later(name: "Alice")).to be_present
          end
        end
      end
    end

    describe 'perform_limit:' do
      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)

        TestJob.good_job_concurrency_rule(
          perform_limit: -> { 0 },
          label: "testlabel"
        )
      end

      it "errors and retry jobs if concurrency is exceeded" do
        active_job = TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")

        performer = GoodJob::JobPerformer.new('*')
        scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
        5.times { scheduler.create_thread }

        sleep_until(max: 10, increments_of: 0.5) do
          GoodJob::Execution.where(active_job_id: active_job.job_id).finished.count >= 1
        end
        scheduler.shutdown

        expect(GoodJob::Job.find_by(active_job_id: active_job.job_id).labels).to include "testlabel"

        expect(GoodJob::Execution.count).to be >= 1
        expect(GoodJob::Execution.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present
      end

      it 'is ignored with the job is executed via perform_now' do
        TestJob.set(good_job_labels: "testlabel").perform_now(name: "Alice")
        expect(JOB_PERFORMED).to be_true
      end

      it 'is ignored when the job is executed inside another job' do
        stub_const("WrapperJob", Class.new(ApplicationJob) do
          def perform
            TestJob.set(good_job_labels: "testlabel").perform_now(name: "Alice")
          end
        end)

        WrapperJob.perform_later
        GoodJob.perform_inline
        expect(JOB_PERFORMED).to be_true
      end
    end

    describe '#enqueue_throttle' do
      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)

        TestJob.good_job_concurrency_rule(
          enqueue_throttle: -> { [1, 1.minute] },
          label: 'testlabel'
        )
      end

      it 'does not enqueue if throttle period has not passed' do
        expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present
        expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be false
        Timecop.travel(61.seconds.from_now) do
          expect(TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")).to be_present
        end
      end
    end

    describe '#perform_throttle' do
      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)

        TestJob.good_job_concurrency_rule(
          perform_throttle: -> { [1, 1.minute] },
          label: 'testlabel'
        )
      end

      it 'does not perform if throttle period has not passed' do
        TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")
        TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")
        TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 1

        Timecop.travel(61.seconds)
        TestJob.set(good_job_labels: "testlabel").perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 2

        Timecop.travel(61.seconds)
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 3
      end
    end

    describe 'perform_limit: with racing claims' do
      let(:rule) { TestJob.good_job_concurrency_rules.first }
      let(:job_a) { TestJob.set(good_job_labels: "testlabel").perform_later(name: "A") }
      let(:job_b) { TestJob.set(good_job_labels: "testlabel").perform_later(name: "B") }

      before do
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: "testlabel")
      end

      def claim(active_job, performed_at)
        GoodJob::Job.find_by(active_job_id: active_job.job_id).update!(performed_at: performed_at)
      end

      def performed_at(active_job)
        GoodJob::Job.find_by(active_job_id: active_job.job_id).performed_at
      end

      def claim_states(active_job)
        GoodJob::ConcurrencyClaim.where(job_id: active_job.job_id).pluck(:state)
      end

      context 'when concurrency claims are migrated' do
        it 'rejects a job whose earlier performed_at committed after another job already passed' do
          claim(job_b, 1.second.ago)
          expect(rule.evaluate(job_b, :perform)).to be_nil

          claim(job_a, 2.seconds.ago)
          expect(rule.evaluate(job_a, :perform)).to eq :limit

          expect(claim_states(job_b)).to eq [GoodJob::ConcurrencyClaim::GRANTED]
          expect(claim_states(job_a)).to eq [GoodJob::ConcurrencyClaim::WAITING]
        end

        it 'allows exactly one of two jobs that claimed before either was checked' do
          claim(job_a, 2.seconds.ago)
          claim(job_b, 1.second.ago)

          expect(rule.evaluate(job_a, :perform)).to eq :limit
          expect(rule.evaluate(job_b, :perform)).to be_nil
        end

        it 'does not count granted claims of jobs that are no longer running' do
          claim(job_b, 1.second.ago)
          expect(rule.evaluate(job_b, :perform)).to be_nil
          GoodJob::Job.find_by(active_job_id: job_b.job_id).update!(finished_at: Time.current)

          claim(job_a, Time.current)
          expect(rule.evaluate(job_a, :perform)).to be_nil
        end
      end

      context 'when concurrency claims are not migrated' do
        before do
          allow(GoodJob::ConcurrencyClaim).to receive(:table_exists?).and_return(false)
        end

        it 'rejects a job whose earlier performed_at committed after another job already passed' do
          claim(job_b, 1.second.ago)
          expect(rule.evaluate(job_b, :perform)).to be_nil

          claim(job_a, 2.seconds.ago)
          expect(rule.evaluate(job_a, :perform)).to eq :limit
          expect(performed_at(job_a)).to be_nil
          expect(performed_at(job_b)).to be_present
        end

        it 'allows exactly one of two jobs that claimed before either was checked' do
          claim(job_a, 2.seconds.ago)
          claim(job_b, 1.second.ago)

          expect(rule.evaluate(job_a, :perform)).to eq :limit
          expect(rule.evaluate(job_b, :perform)).to be_nil
        end
      end
    end

    describe 'perform_limit: separate label and legacy key scopes' do
      it 'does not share claims between a label and a legacy key with the same value' do
        TestJob.good_job_control_concurrency_with(perform_limit: 1, key: 'label:shared')
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: 'shared')
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: 'key:shared')
        legacy_job = TestJob.perform_later(name: 'legacy')
        label_job = TestJob.set(good_job_labels: ['shared', 'key:shared']).perform_later(name: 'label')
        legacy_rule = described_class::Rule.new(key: 'label:shared', perform_limit: 1)

        GoodJob::Job.find_by(active_job_id: legacy_job.job_id).update!(performed_at: Time.current)
        expect(legacy_rule.evaluate(legacy_job, :perform)).to be_nil

        GoodJob::Job.find_by(active_job_id: label_job.job_id).update!(performed_at: Time.current)
        TestJob.good_job_concurrency_rules.each do |rule|
          expect(rule.evaluate(label_job, :perform)).to be_nil
        end
        expect(GoodJob::ConcurrencyClaim.where(job_id: legacy_job.job_id).pluck(:key)).to eq ['key:label:shared']
        expect(GoodJob::ConcurrencyClaim.where(job_id: label_job.job_id).pluck(:key)).to contain_exactly('label:shared', 'label:key:shared')
        expect(legacy_rule.evaluate(label_job, :perform)).to eq :limit
      end
    end

    describe 'perform_limit: promotion of waiting jobs' do
      before do
        stub_const 'HOLD', Queue.new
        stub_const 'ENTERED', Queue.new
        stub_const 'HoldingJob', (Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Concurrency

          good_job_concurrency_rule(perform_limit: 1, label: "holding")
          self.good_job_labels = ["holding"]

          def perform
            ENTERED << job_id
            HOLD.pop
          end
        end)
      end

      it 'runs a rejected job immediately when the job holding its claim finishes' do
        holder = HoldingJob.perform_later
        expect(holder).to be_present
        holder_thread = Thread.new do
          Rails.application.executor.wrap { GoodJob::Job.perform_with_lock(lock_id: SecureRandom.uuid) }
        end
        Timeout.timeout(5) { ENTERED.pop }

        waiter = HoldingJob.perform_later
        Rails.application.executor.wrap { GoodJob::Job.perform_with_lock(lock_id: SecureRandom.uuid) }

        waiter_record = GoodJob::Job.find_by(active_job_id: waiter.job_id)
        expect(waiter_record.scheduled_at).to be > Time.current
        expect(GoodJob::ConcurrencyClaim.where(job_id: waiter.job_id).pluck(:state)).to eq [GoodJob::ConcurrencyClaim::WAITING]

        HOLD << true
        expect(holder_thread.join(5)).to be_truthy
        expect(holder_thread.value).to be_present

        expect(waiter_record.reload.scheduled_at).to be <= Time.current
        expect(GoodJob::ConcurrencyClaim.where(job_id: holder.job_id)).to be_empty
      end
    end

    describe 'perform_limit: with both a label and a key' do
      before do
        allow(GoodJob.deprecator).to receive(:warn)
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: "testlabel", key: -> { "custom" })
      end

      it 'uses the label for both enqueue and perform locks and claims' do
        TestJob.good_job_concurrency_rules = []
        TestJob.good_job_concurrency_rule(enqueue_limit: 1, perform_limit: 1, label: "testlabel", key: -> { "custom" })
        allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
        active_job = TestJob.set(good_job_labels: "testlabel").perform_later(name: "A")
        GoodJob::Job.find_by(active_job_id: active_job.job_id).update!(performed_at: Time.current)

        expect(TestJob.good_job_concurrency_rules.first.evaluate(active_job, :perform)).to be_nil
        expect(GoodJob::Job).to have_received(:advisory_lock_key).with("label:testlabel", function: "pg_advisory_xact_lock").twice
        expect(GoodJob::ConcurrencyClaim.where(job_id: active_job.job_id).pluck(:key)).to eq ["label:testlabel"]
      end

      it 'does not evaluate the ignored custom key' do
        rule = described_class::Rule.new(label: "testlabel", key: -> { raise 'Custom key evaluated' }, perform_limit: 1)
        active_job = TestJob.set(good_job_labels: "testlabel").perform_later(name: nil)
        GoodJob::Job.find_by(active_job_id: active_job.job_id).update!(performed_at: Time.current)

        expect(rule.evaluate(active_job, :perform)).to be_nil
      end

      it 'grants only one of two concurrent promoted jobs with different custom keys' do
        jobs = %w[A B].map do |name|
          active_job = TestJob.set(good_job_labels: "testlabel").perform_later(name: name)
          GoodJob::Job.find_by(active_job_id: active_job.job_id).update!(performed_at: Time.current)
          GoodJob::ConcurrencyClaim.create!(key: "label:testlabel", job_id: active_job.job_id, state: GoodJob::ConcurrencyClaim::PROMOTED)
          active_job
        end
        rule = described_class::Rule.new(label: "testlabel", key: -> { "key-#{arguments.first[:name]}" }, perform_limit: 1)
        barrier = Concurrent::CyclicBarrier.new(2)
        threads = jobs.map do |active_job|
          Thread.new do
            GoodJob::Job.connection_pool.with_connection do
              raise 'Concurrent checks did not start' unless barrier.wait(5)

              rule.evaluate(active_job, :perform)
            end
          end
        end

        expect(threads.map(&:value)).to contain_exactly(nil, :limit)
      ensure
        threads&.each { |thread| thread.join(5) }
      end
    end

    describe 'perform_limit: with multiple rules' do
      before do
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: "first")
        TestJob.good_job_concurrency_rule(perform_limit: 1, label: "second")
      end

      it 'releases claims granted by earlier rules and waits only on the rejecting rule' do
        blocker = TestJob.set(good_job_labels: ["second"]).perform_later(name: "blocker")
        GoodJob::Job.find_by(active_job_id: blocker.job_id).update!(performed_at: Time.current)
        expect(TestJob.good_job_concurrency_rules.last.evaluate(blocker, :perform)).to be_nil

        waiter = TestJob.set(good_job_labels: %w[first second]).perform_later(name: "waiter")
        waiter_record = GoodJob::Job.find_by(active_job_id: waiter.job_id)
        waiter_record.update!(performed_at: Time.current)
        allow(GoodJob::CurrentThread).to receive(:job).and_return(waiter_record)

        expect { waiter.run_callbacks(:perform) }.to raise_error(GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError)

        expect(GoodJob::ConcurrencyClaim.where(job_id: waiter.job_id).pluck(:key, :state)).to eq [["label:second", GoodJob::ConcurrencyClaim::WAITING]]
      end
    end

    describe 'perform_limit: together with perform_throttle:' do
      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)

        TestJob.good_job_control_concurrency_with(
          perform_limit: -> { 1 },
          perform_throttle: -> { [1, 1.minute] },
          key: -> { arguments.first[:name] }
        )
      end

      it 'does not perform if throttle period has not passed' do
        TestJob.perform_later(name: "Alice")
        TestJob.perform_later(name: "Alice")
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 1

        Timecop.travel(61.seconds)
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 2

        Timecop.travel(61.seconds)
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 3
      end
    end
  end

  describe "legacy functionality" do
    describe 'when concurrency key returns nil' do
      it 'does not limit concurrency' do
        TestJob.good_job_control_concurrency_with(
          total_limit: -> { 1 },
          key: -> {}
        )

        expect(TestJob.perform_later(name: "Alice")).to be_present
        expect(TestJob.perform_later(name: "Alice")).to be_present
      end
    end

    describe 'when concurrency key is nil' do
      it 'does not limit concurrency' do
        TestJob.good_job_control_concurrency_with(
          total_limit: -> { 1 },
          key: nil
        )

        expect(TestJob.perform_later(name: "Alice")).to be_present
        expect(TestJob.perform_later(name: "Alice")).to be_present
      end
    end

    describe '.good_job_control_concurrency_with' do
      describe 'total_limit:' do
        before do
          TestJob.good_job_control_concurrency_with(
            total_limit: -> { 1 },
            key: -> { arguments.first[:name] }
          )
        end

        it "does not enqueue if limit is exceeded for a particular key" do
          expect(TestJob.perform_later(name: "Alice")).to be_present
          expect(TestJob.perform_later(name: "Alice")).to be false
        end

        it "is inclusive of both performing and enqueued jobs" do
          expect(TestJob.perform_later(name: "Alice")).to be_present

          Rails.application.executor.wrap do
            GoodJob::Job.all.with_advisory_lock do
              expect(TestJob.perform_later(name: "Alice")).to be false
            end
          end
        end
      end

      describe 'enqueue_limit:' do
        before do
          TestJob.good_job_control_concurrency_with(
            enqueue_limit: -> { 2 },
            key: -> { arguments.first[:name] }
          )
        end

        it "does not enqueue if enqueue concurrency limit is exceeded for a particular key" do
          abort_events = []
          enqueue_events = []
          enqueue_callback = ->(*args) { enqueue_events << ActiveSupport::Notifications::Event.new(*args) }
          abort_callback = ->(*args) { abort_events << ActiveSupport::Notifications::Event.new(*args) }

          ActiveSupport::Notifications.subscribed(enqueue_callback, "enqueue.active_job") do
            ActiveSupport::Notifications.subscribed(abort_callback, "enqueue_concurrency_limit_exceeded.good_job") do
              expect(TestJob.perform_later(name: "Alice")).to be_present
              expect(TestJob.perform_later(name: "Alice")).to be_present

              # Third usage of key does not enqueue
              expect(TestJob.perform_later(name: "Alice")).to be false

              # Usage of different key does enqueue
              expect(TestJob.perform_later(name: "Bob")).to be_present
            end
          end

          expect(GoodJob::Job.where(concurrency_key: "Alice").count).to eq 2
          expect(GoodJob::Job.where(concurrency_key: "Bob").count).to eq 1

          expect(abort_events.size).to eq 1
          expect(abort_events.first.payload).to include(key: 'Alice', limit: 2)
          expect(abort_events.first.payload[:job]).to be_a(TestJob)

          # Aborted enqueues must not be logged as successfully enqueued (regression: PR #820).
          successful = enqueue_events.reject { |e| e.payload[:aborted] }
          expect(successful.count { |e| e.payload[:job].arguments == [{ name: "Alice" }] }).to eq 2
          expect(successful.count { |e| e.payload[:job].arguments == [{ name: "Bob" }] }).to eq 1
        end

        it 'excludes jobs that are already executing/locked' do
          expect(TestJob.perform_later(name: "Alice")).to be_present
          expect(TestJob.perform_later(name: "Alice")).to be_present

          # Lock one of the jobs
          Rails.application.executor.wrap do
            GoodJob::Job.first.with_advisory_lock do
              # Third usage does enqueue
              expect(TestJob.perform_later(name: "Alice")).to be_present
            end
          end
        end
      end

      describe 'perform_limit:' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(true)

          TestJob.good_job_control_concurrency_with(
            perform_limit: -> { 0 },
            key: -> { arguments.first[:name] }
          )
        end

        it "errors and retry jobs if concurrency is exceeded" do
          active_job = TestJob.perform_later(name: "Alice")

          performer = GoodJob::JobPerformer.new('*')
          scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
          5.times { scheduler.create_thread }

          sleep_until(max: 10, increments_of: 0.5) do
            GoodJob::Execution.where(active_job_id: active_job.job_id).finished.count >= 1
          end
          scheduler.shutdown

          expect(GoodJob::Job.find_by(active_job_id: active_job.job_id).concurrency_key).to eq "Alice"

          expect(GoodJob::Execution.count).to be >= 1
          expect(GoodJob::Execution.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present
        end

        it 'is ignored with the job is executed via perform_now' do
          TestJob.perform_now(name: "Alice")
          expect(JOB_PERFORMED).to be_true
        end

        it 'is ignored when the job is executed inside another job' do
          stub_const("WrapperJob", Class.new(ApplicationJob) do
            def perform
              TestJob.perform_now(name: "Alice")
            end
          end)

          WrapperJob.perform_later
          GoodJob.perform_inline
          expect(JOB_PERFORMED).to be_true
        end
      end

      describe '#enqueue_throttle' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(true)

          TestJob.good_job_control_concurrency_with(
            enqueue_throttle: -> { [1, 1.minute] },
            key: -> { arguments.first[:name] }
          )
        end

        it 'does not enqueue if throttle period has not passed' do
          expect(TestJob.perform_later(name: "Alice")).to be_present
          expect(TestJob.perform_later(name: "Alice")).to be false
          Timecop.travel(61.seconds.from_now) do
            expect(TestJob.perform_later(name: "Alice")).to be_present
          end
        end
      end

      describe '#perform_throttle' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(true)

          TestJob.good_job_control_concurrency_with(
            perform_throttle: -> { [1, 1.minute] },
            key: -> { arguments.first[:name] }
          )
        end

        it 'does not perform if throttle period has not passed' do
          TestJob.perform_later(name: "Alice")
          TestJob.perform_later(name: "Alice")
          TestJob.perform_later(name: "Alice")
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 1

          Timecop.travel(61.seconds)
          TestJob.perform_later(name: "Alice")
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 2

          Timecop.travel(61.seconds)
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 3
        end
      end

      describe 'perform_limit: together with perform_throttle:' do
        before do
          allow(GoodJob).to receive(:preserve_job_records).and_return(true)

          TestJob.good_job_control_concurrency_with(
            perform_limit: -> { 1 },
            perform_throttle: -> { [1, 1.minute] },
            key: -> { arguments.first[:name] }
          )
        end

        it 'does not perform if throttle period has not passed' do
          TestJob.perform_later(name: "Alice")
          TestJob.perform_later(name: "Alice")
          TestJob.perform_later(name: "Alice")
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 1

          Timecop.travel(61.seconds)
          TestJob.perform_later(name: "Alice")
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 2

          Timecop.travel(61.seconds)
          GoodJob.perform_inline

          expect(GoodJob::Job.finished.count).to eq 3
        end
      end
    end

    describe '#good_job_concurrency_key' do
      context 'when retrying a job' do
        before do
          stub_const 'TestJob', (Class.new(ActiveJob::Base) do
            include GoodJob::ActiveJobExtensions::Concurrency

            good_job_control_concurrency_with(
              total_limit: 1,
              key: -> { Time.current.to_f }
            )
            retry_on StandardError

            def perform(*)
              raise "ERROR"
            end
          end)
        end

        describe 'retries' do
          it 'preserves the value' do
            TestJob.set(wait_until: 5.minutes.ago).perform_later(name: "Alice")

            begin
              GoodJob.perform_inline
            rescue StandardError
              nil
            end

            expect(GoodJob::Job.count).to eq 1
            expect(GoodJob::Job.first.concurrency_key).to be_present
            expect(GoodJob::Job.first).not_to be_finished
          end
        end
      end

      context 'when no key is specified' do
        before do
          stub_const 'TestJob', (Class.new(ActiveJob::Base) do
            include GoodJob::ActiveJobExtensions::Concurrency

            def perform(name)
            end
          end)
        end

        it 'uses the class name as the default concurrency key' do
          job = TestJob.perform_later("Alice")
          expect(job.good_job_concurrency_key).to eq('TestJob')
        end
      end

      describe '#perform_later' do
        before do
          stub_const 'TestJob', (Class.new(ActiveJob::Base) do
            include GoodJob::ActiveJobExtensions::Concurrency

            good_job_control_concurrency_with(
              total_limit: 1,
              key: -> { arguments.first }
            )

            def perform(arg)
            end
          end)
        end

        it 'raises an error for non-serializable types' do
          expect { TestJob.perform_later({ key: "value" }) }.to raise_error(TypeError, "Concurrency key must be a String; was a Hash")
          expect { TestJob.perform_later({ key: "value" }.with_indifferent_access) }.to raise_error(TypeError)
          expect { TestJob.perform_later(["key"]) }.to raise_error(TypeError)
          expect { TestJob.perform_later(TestJob) }.to raise_error(TypeError)
        end
      end
    end
  end
end
