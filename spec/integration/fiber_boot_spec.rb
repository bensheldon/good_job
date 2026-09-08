# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Fiber application boot' do
  def boot(fibers:, reloading:, environment: 'test')
    output, status = Open3.capture2e(
      { 'GOOD_JOB_FIBERS' => fibers, 'GOOD_JOB_EXECUTION_MODE' => 'external', 'GOOD_JOB_ENABLE_CRON' => 'false',
        'DATABASE_URL' => ENV.fetch('DATABASE_URL', 'postgresql://localhost/good_job_test'),
        'SECRET_KEY_BASE' => 'fiber-boot-test-' * 8,
        'RAILS_ENV' => environment, 'CI' => 'true', 'TEST_RELOADING' => reloading.to_s },
      RbConfig.ruby, '-rbundler/setup', '-e', <<~'RUBY'
        require './demo/config/application'
        Rails.application.config.cache_classes = ENV['TEST_RELOADING'] != 'true'
        # Prevent the demo app from starting schedulers and cron during boot.
        GoodJob::CLI.within_exe = true
        Rails.application.initialize!
        GoodJob::CLI.within_exe = false
        configuration = GoodJob::Configuration.new({ execution_mode: :async, max_threads: 2, queues: 'serial:1;io:8' })
        scheduler = GoodJob::MultiScheduler.from_configuration(configuration)
        state = {
          isolation: (ActiveSupport::IsolatedExecutionState.isolation_level if defined?(ActiveSupport::IsolatedExecutionState)),
          schedulers: scheduler.stats[:schedulers],
          lock_strategy: configuration.lock_strategy,
        }
        scheduler.shutdown
        GoodJob.shutdown
        puts "BOOT_RESULT=#{JSON.generate(state)}"
      RUBY
    )
    expect(status).to be_success, output
    JSON.parse(output.lines.find { |line| line.start_with?('BOOT_RESULT=') }.delete_prefix('BOOT_RESULT='))
  end

  [nil, '', '0', 'false', ' FaLsE '].each do |value|
    it "boots without enabling fiber isolation for #{value.inspect}" do
      result = boot(fibers: value, reloading: true)
      expect(result['isolation']).not_to eq 'fiber'
      expect(result['schedulers'].pluck('max_fibers')).to all(be_nil)
      expect(result['schedulers'].pluck('max_threads')).to eq [1, 8]
    end
  end

  it 'boots development with an invalid value and falls back to capped threads' do
    result = boot(fibers: 'junk', reloading: true, environment: 'development')
    expect(result['schedulers'].pluck('max_threads')).to eq [1, 2]
    expect(result['lock_strategy']).to eq 'advisory'
  end

  it 'boots the demo environment and falls back for invalid fiber configuration' do
    result = boot(fibers: 'junk', reloading: false, environment: 'demo')
    expect(result['schedulers'].pluck('max_threads')).to eq [1, 2]
    expect(result['lock_strategy']).to eq 'advisory'
  end

  it 'falls back in development when reloading is enabled', :fiber_isolation, :requires_async do
    result = boot(fibers: ' TrUe ', reloading: true, environment: 'development')
    expect(result['isolation']).to eq 'fiber'
    expect(result['schedulers'].pluck('max_threads')).to eq [1, 2]
  end

  it 'enables fibers when reloading is disabled', :fiber_isolation, :requires_async do
    result = boot(fibers: '25', reloading: false)
    expect(result['schedulers'].pluck('max_fibers')).to eq [1, 8]
    expect(result['lock_strategy']).to eq 'advisory'
  end
end
