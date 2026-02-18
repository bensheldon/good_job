# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Configuration do
  describe '.total_estimated_threads' do
    before do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(2)
    end

    it 'counts up the total estimated threads' do
      expect(described_class.total_estimated_threads).to eq 2
    end

    it 'outputs a warning message' do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(0)
      allow(GoodJob.logger).to receive(:warn)

      described_class.total_estimated_threads(warn: true)

      expect(GoodJob.logger).to have_received(:warn).with(/GoodJob is using \d+ threads/)
    end
  end

  describe '#execution_mode' do
    context 'when in development' do
      before do
        allow(Rails).to receive(:env) { "development".inquiry }
      end

      it 'defaults to :inline' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :async
      end
    end

    context 'when in test' do
      before do
        allow(Rails).to receive(:env) { "test".inquiry }
      end

      it 'defaults to :inline' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :inline
      end
    end

    context 'when in production' do
      before do
        allow(Rails).to receive(:env) { "production".inquiry }
      end

      it 'defaults to :external' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :external
      end
    end
  end

  describe '#cleanup_discarded_jobs?' do
    it 'defaults to true' do
      configuration = described_class.new({})
      expect(configuration.cleanup_discarded_jobs?).to be true
    end

    context 'when rails config is set' do
      before do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_discarded_jobs: false })
      end

      it 'uses rails config value' do
        configuration = described_class.new({})
        expect(configuration.cleanup_discarded_jobs?).to be false
      end
    end

    context 'when environment variable is set' do
      before do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_DISCARDED_JOBS' => 'false' })
      end

      it 'uses environment variable' do
        configuration = described_class.new({})
        expect(configuration.cleanup_discarded_jobs?).to be false
      end
    end
  end

  describe '#cleanup_preserved_jobs_before_seconds_ago' do
    it 'defaults to 14 days' do
      configuration = described_class.new({})
      expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 14.days.to_i
    end

    context 'when environment variable is set' do
      before do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO' => '36000' })
      end

      context 'when option is given' do
        it 'uses option value' do
          configuration = described_class.new({ before_seconds_ago: 10000 })
          expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 10000
        end
      end

      context 'when option is not given' do
        it 'uses environment variable' do
          configuration = described_class.new({})
          expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 36000
        end
      end
    end
  end

  describe '#cleanup_interval_jobs' do
    it 'defaults to 1000' do
      configuration = described_class.new({})
      expect(configuration.cleanup_interval_jobs).to eq 1000
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: 10000 })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq 10000
      end

      it 'can be disabled with false' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: false })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be false
      end

      it 'coerces 0 to false' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: 0 })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq false
      end

      it 'coerces nil to default' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: nil })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be described_class::DEFAULT_CLEANUP_INTERVAL_JOBS
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '50000' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq 50000
      end

      it 'always runs with -1' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '-1' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq(-1)
      end

      it 'coerces 0 to false' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '0' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be false
      end

      it 'coerces empty value to default' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be described_class::DEFAULT_CLEANUP_INTERVAL_JOBS
      end
    end
  end

  describe '#cleanup_interval_seconds' do
    it 'defaults to 10 minutes' do
      configuration = described_class.new({})
      expect(configuration.cleanup_interval_seconds).to eq 10.minutes.to_i
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: 1.hour })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to eq 3600
      end

      it 'can be disabled with false' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: false })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be false
      end

      it 'coerces 0 to false' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: 0 })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be false
      end

      it 'coerces nil to default value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: nil })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be described_class::DEFAULT_CLEANUP_INTERVAL_SECONDS
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '7200' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to eq 7200
      end

      it 'can be disabled with -1' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '-1' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to eq(-1)
      end

      it 'coerces 0 to false' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '0' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be false
      end

      it 'coerces empty value to default' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be described_class::DEFAULT_CLEANUP_INTERVAL_SECONDS
      end
    end
  end

  describe '#cron' do
    let(:cron) { { some_task: { cron: "every day", class: "FooJob" } } }

    before do
      stub_const 'ENV', ENV.to_hash.except('GOOD_JOB_CRON')
      allow(Rails.application.config).to receive(:good_job).and_return({})
    end

    it 'returns entries specified in options' do
      configuration = described_class.new({ cron: cron })

      expect(configuration.cron).to eq(cron)
    end

    it 'returns entries specified in rails config' do
      allow(Rails.application.config).to receive(:good_job).and_return({ cron: cron })

      configuration = described_class.new({})

      expect(configuration.cron).to eq(cron)
    end

    it 'returns entries specified in ENV' do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CRON' => cron.to_json })

      configuration = described_class.new({})

      expect(configuration.cron).to eq(cron)
    end

    it 'returns an empty hash without any entry specified' do
      configuration = described_class.new({})

      expect(configuration.cron).to eq({})
    end

    it 'has a graceful restart period' do
      allow(Rails.application.config).to receive(:good_job).and_return({ cron_graceful_restart_period: 5.minutes })
      expect(described_class.new({}).cron_graceful_restart_period).to eq 5.minutes
    end
  end

  describe '#enable_listen_notify' do
    it 'defaults to true' do
      configuration = described_class.new({})
      expect(configuration.enable_listen_notify).to be true
    end

    it 'can set false with 0 from ENV' do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_ENABLE_LISTEN_NOTIFY' => '0' })

      configuration = described_class.new({})
      expect(configuration.enable_listen_notify).to be false
    end
  end

  describe '#dashboard_default_locale' do
    it 'delegates to rails configuration' do
      allow(Rails.application.config).to receive(:good_job).and_return({ dashboard_default_locale: :de })
      configuration = described_class.new({})
      expect(configuration.dashboard_default_locale).to eq :de
    end
  end

  describe '#dashboard_live_poll_enabled' do
    it 'delegates to rails configuration' do
      allow(Rails.application.config).to receive(:good_job).and_return({ dashboard_live_poll_enabled: false })
      configuration = described_class.new({})
      expect(configuration.dashboard_live_poll_enabled).to eq false
    end

    it 'has a "true" default value' do
      configuration = described_class.new({})
      expect(configuration.dashboard_live_poll_enabled).to eq true
    end
  end

  describe '#advisory_lock_heartbeat' do
    it 'defaults to true in development' do
      allow(Rails).to receive(:env) { "development".inquiry }
      configuration = described_class.new({})
      expect(configuration.advisory_lock_heartbeat).to be true
    end

    it 'defaults to false in other environments' do
      allow(Rails).to receive(:env) { "production".inquiry }
      configuration = described_class.new({})
      expect(configuration.advisory_lock_heartbeat).to be false
    end

    it 'can be overridden by options' do
      configuration = described_class.new({ advisory_lock_heartbeat: true })
      expect(configuration.advisory_lock_heartbeat).to be true
    end

    it 'can be overridden by rails config' do
      allow(Rails.application.config).to receive(:good_job).and_return({ advisory_lock_heartbeat: true })
      configuration = described_class.new({})
      expect(configuration.advisory_lock_heartbeat).to be true
    end

    it 'can be overridden by environment variable' do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_ADVISORY_LOCK_HEARTBEAT' => 'true' })
      configuration = described_class.new({})
      expect(configuration.advisory_lock_heartbeat).to be true
    end
  end

  describe '#environment' do
    it 'defaults to Rails.env' do
      allow(Rails).to receive(:env) { "production".inquiry }
      configuration = described_class.new({})
      expect(configuration.environment).to eq "production"
    end

    it 'can be overridden by options' do
      configuration = described_class.new({ environment: "staging" })
      expect(configuration.environment).to eq "staging"
    end

    it 'can be overridden by rails config' do
      allow(Rails.application.config).to receive(:good_job).and_return({ environment: "staging" })
      configuration = described_class.new({})
      expect(configuration.environment).to eq "staging"
    end

    it 'can be overridden by environment variable' do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_ENVIRONMENT' => 'staging' })
      configuration = described_class.new({})
      expect(configuration.environment).to eq "staging"
    end

    it 'prioritizes options over rails config' do
      allow(Rails.application.config).to receive(:good_job).and_return({ environment: "staging" })
      configuration = described_class.new({ environment: "custom" })
      expect(configuration.environment).to eq "custom"
    end

    it 'prioritizes rails config over environment variable' do
      allow(Rails.application.config).to receive(:good_job).and_return({ environment: "staging" })
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_ENVIRONMENT' => 'env_var' })
      configuration = described_class.new({})
      expect(configuration.environment).to eq "staging"
    end
  end
end
