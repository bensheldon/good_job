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

  describe '#threads' do
    it 'defaults to DEFAULT_THREADS' do
      expect(described_class.new({}).threads).to eq described_class::DEFAULT_THREADS
    end

    it 'reads the :threads option' do
      expect(described_class.new({ threads: 7 }).threads).to eq 7
    end

    it 'reads the GOOD_JOB_THREADS environment variable' do
      configuration = described_class.new({}, env: { 'GOOD_JOB_THREADS' => '9' })
      expect(configuration.threads).to eq 9
    end

    it 'falls back to RAILS_MAX_THREADS' do
      configuration = described_class.new({}, env: { 'RAILS_MAX_THREADS' => '3' })
      expect(configuration.threads).to eq 3
    end

    context 'with the deprecated max_threads sources' do
      it 'reads and warns for the :max_threads option' do
        configuration = described_class.new({ max_threads: 4 })
        expect(GoodJob.deprecator).to receive(:warn).with(/max_threads.*option.*deprecated/i)
        expect(configuration.threads).to eq 4
      end

      it 'reads and warns for the GOOD_JOB_MAX_THREADS environment variable' do
        configuration = described_class.new({}, env: { 'GOOD_JOB_MAX_THREADS' => '6' })
        expect(GoodJob.deprecator).to receive(:warn).with(/GOOD_JOB_MAX_THREADS.*deprecated/i)
        expect(configuration.threads).to eq 6
      end

      it 'prefers the new sources without warning' do
        configuration = described_class.new({ threads: 8 }, env: { 'GOOD_JOB_MAX_THREADS' => '6' })
        expect(GoodJob.deprecator).not_to receive(:warn)
        expect(configuration.threads).to eq 8
      end
    end
  end

  describe '#max_threads' do
    it 'is a backwards-compatible alias of #threads' do
      expect(described_class.new({ threads: 5 }).max_threads).to eq 5
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

    it 'has no graceful restart period by default' do
      expect(described_class.new({}).cron_graceful_restart_period).to be_nil
    end

    it 'converts an integer graceful restart period to a duration' do
      allow(Rails.application.config).to receive(:good_job).and_return({ cron_graceful_restart_period: 300 })
      expect(described_class.new({}).cron_graceful_restart_period).to be_a(ActiveSupport::Duration).and eq(5.minutes)
    end

    it 'reads the graceful restart period from the environment in seconds' do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CRON_GRACEFUL_RESTART_PERIOD' => '300' })
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

  describe '#queue_select_limit' do
    it 'defaults to 1000' do
      configuration = described_class.new({})
      expect(configuration.queue_select_limit).to eq 1000
    end

    context 'when option is given' do
      it 'uses option value' do
        configuration = described_class.new({ queue_select_limit: 100 })
        expect(configuration.queue_select_limit).to eq 100
      end
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ queue_select_limit: 500 })
        configuration = described_class.new({})
        expect(configuration.queue_select_limit).to eq 500
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_QUEUE_SELECT_LIMIT' => '2000' })
        configuration = described_class.new({})
        expect(configuration.queue_select_limit).to eq 2000
      end
    end
  end

  describe '#subprocesses' do
    it 'defaults to 0' do
      configuration = described_class.new({})
      expect(configuration.subprocesses).to eq 0
    end

    context 'when option is given' do
      it 'uses the option value' do
        configuration = described_class.new({ subprocesses: 3 })
        expect(configuration.subprocesses).to eq 3
      end
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ subprocesses: 2 })
        configuration = described_class.new({})
        expect(configuration.subprocesses).to eq 2
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_SUBPROCESSES' => '4' })
        configuration = described_class.new({})
        expect(configuration.subprocesses).to eq 4
      end
    end
  end

  describe '#cluster?' do
    it 'is false when subprocesses is 0' do
      configuration = described_class.new({ subprocesses: 0 })
      expect(configuration.cluster?).to be false
    end

    context 'when subprocesses is positive' do
      it 'is true when the platform supports fork' do
        allow(Process).to receive(:respond_to?).and_call_original
        allow(Process).to receive(:respond_to?).with(:fork).and_return(true)
        configuration = described_class.new({ subprocesses: 1 })
        expect(configuration.cluster?).to be true
      end

      it 'is false when the platform does not support fork' do
        allow(Process).to receive(:respond_to?).and_call_original
        allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
        configuration = described_class.new({ subprocesses: 2 })
        expect(configuration.cluster?).to be false
      end
    end

    context 'when the queue string has pipe-delimited pools' do
      it 'derives the count from the number of pools' do
        configuration = described_class.new({ queues: 'elephant:2|mice:3' })
        expect(configuration.subprocesses).to eq(2)
      end

      it 'enables cluster mode even without a configured count' do
        allow(Process).to receive(:respond_to?).and_call_original
        allow(Process).to receive(:respond_to?).with(:fork).and_return(true)
        configuration = described_class.new({ queues: 'elephant|mice' })
        expect(configuration.cluster?).to be true
      end
    end
  end

  describe '#subprocess_configs' do
    it 'returns one identical configuration per subprocess for a homogeneous queue string' do
      configuration = described_class.new({ subprocesses: 3, queues: 'default,-mailers' })
      configs = configuration.subprocess_configs

      expect(configs.size).to eq(3)
      expect(configs.map(&:queue_string)).to all(eq('default,-mailers'))
    end

    it 'returns one configuration per pipe-delimited pool' do
      configuration = described_class.new({ queues: 'elephant:2|mice:3' })

      expect(configuration.subprocess_configs.map(&:queue_string)).to eq(['elephant:2', 'mice:3'])
    end

    it 'warns and ignores the configured count when pipe-delimited pools are given' do
      allow(GoodJob.logger).to receive(:warn)
      configuration = described_class.new({ subprocesses: 5, queues: 'elephant|mice' })

      expect(configuration.subprocess_configs.size).to eq(2)
      expect(GoodJob.logger).to have_received(:warn).with(/ignored/)
    end
  end

  describe '#flattened_queue_string' do
    it 'rewrites pipe-delimited subprocess pools as semicolon-delimited scheduler groups' do
      configuration = described_class.new({ queues: 'elephant:2 | mice:3' })
      expect(configuration.flattened_queue_string).to eq('elephant:2;mice:3')
    end

    it 'is unchanged when there are no pipe-delimited pools' do
      configuration = described_class.new({ queues: 'default,-mailers:2;mice:3' })
      expect(configuration.flattened_queue_string).to eq('default,-mailers:2;mice:3')
    end
  end

  describe '#in_webserver?' do
    let(:configuration) { described_class.new({}) }

    it 'is false outside of a web server' do
      allow(configuration).to receive(:caller).and_return(["/app/bin/good_job:5:in '<main>'"])
      expect(configuration.in_webserver?).to be false
    end

    it 'is true in a Puma worker boot hook' do
      worker_boot_caller = [
        "/gems/puma-7.2.0/lib/puma/configuration.rb:340:in 'Puma::Configuration#run_hooks'",
        "/gems/puma-7.2.0/lib/puma/cluster/worker.rb:58:in 'Puma::Cluster::Worker#run'",
        "/gems/puma-7.2.0/lib/puma/cluster.rb:106:in 'Puma::Cluster#spawn_worker'",
        "/gems/puma-7.2.0/lib/puma/launcher.rb:208:in 'Puma::Launcher#run'",
      ]
      allow(configuration).to receive(:caller).and_return(worker_boot_caller)
      expect(configuration.in_webserver?).to be true
    end

    it 'is true in a Puma 8 request' do
      request_caller = [
        "/gems/puma-8.0.2/lib/puma/response.rb:78:in 'Puma::Response#handle_request'",
        "/gems/puma-8.0.2/lib/puma/server.rb:508:in 'Puma::Server#process_client'",
      ]
      allow(configuration).to receive(:caller).and_return(request_caller)
      expect(configuration.in_webserver?).to be true
    end

    it 'is true in a Puma cluster worker without the launcher in the stack' do
      cluster_caller = [
        "/gems/puma-6.4.3/lib/puma/cluster/worker.rb:57:in `run'",
        "/gems/puma-6.4.3/lib/puma/cluster.rb:216:in `worker'",
      ]
      allow(configuration).to receive(:caller).and_return(cluster_caller)
      expect(configuration.in_webserver?).to be true
    end

    it 'is true in Puma single process mode' do
      single_caller = [
        "/gems/puma-7.2.0/lib/puma/single.rb:44:in `run'",
        "/gems/puma-7.2.0/lib/puma/launcher.rb:208:in `run'",
      ]
      allow(configuration).to receive(:caller).and_return(single_caller)
      expect(configuration.in_webserver?).to be true
    end

    it 'is false in the Puma cluster master' do
      master_caller = [
        "/gems/puma-7.2.0/lib/puma/configuration.rb:340:in `run_hooks'",
        "/gems/puma-7.2.0/lib/puma/cluster.rb:438:in `run'",
        "/gems/puma-7.2.0/lib/puma/launcher.rb:208:in `run'",
      ]
      allow(configuration).to receive(:caller).and_return(master_caller)
      expect(configuration.in_webserver?).to be false
    end
  end
end
