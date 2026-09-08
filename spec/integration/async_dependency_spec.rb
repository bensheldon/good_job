# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Optional Async dependency' do
  it 'loads GoodJob and runs a thread task without loading Async' do
    output, status = Open3.capture2e(RbConfig.ruby, '-rbundler/setup', '-Ilib', '-e', <<~RUBY)
      require 'good_job'
      abort 'Async was loaded by GoodJob' if defined?(Async)
      result = Queue.new
      executor = Concurrent::ThreadPoolExecutor.new(max_threads: 1)
      executor.post { result << :done }
      abort 'thread execution failed' unless result.pop == :done
      executor.shutdown
      abort 'thread did not stop' unless executor.wait_for_termination(5)
      abort 'thread execution loaded Async' if defined?(Async)
      if RUBY_ENGINE == 'jruby'
        abort 'Async is installed in the JRuby bundle' if Gem.loaded_specs.key?('async')
      end
      puts 'thread-only ok'
    RUBY
    expect(status).to be_success, output
    expect(output).to include('thread-only ok')
  end

  it 'checks the installed Async version before enabling fibers' do
    output, status = Open3.capture2e(RbConfig.ruby, '-rbundler/setup', '-Ilib', '-e', <<~RUBY)
      require 'good_job'
      expected = ENV['GOOD_JOB_TEST_ASYNC']
      minimum = Gem.ruby_version >= Gem::Version.new('4.0') ? '2.25' : '2.24'
      unsupported = expected == 'absent' || (expected && !expected.start_with?('>') && Gem::Version.new(expected) < Gem::Version.new(minimum))
      if expected == 'absent'
        abort 'Async unexpectedly installed' if Gem.loaded_specs.key?('async')
      elsif expected && !expected.start_with?('>')
        abort 'Wrong Async version' unless Gem.loaded_specs.fetch('async').version.to_s == expected
      end
      begin
        GoodJob::Scheduler.send(:validate_fiber_runtime!)
        abort 'accepted unsupported Async' if unsupported
        Async { sleep 0.001 }.wait
      rescue ArgumentError => e
        supported_ruby = RUBY_ENGINE == 'ruby' && Gem.ruby_version >= Gem::Version.new('3.2')
        if supported_ruby && expected == 'absent'
          abort e.message unless e.message.include?('Gemfile') && e.message.include?('async')
        elsif supported_ruby && unsupported
          abort e.message unless e.message.include?(">= " + minimum) && e.message.include?(expected)
        elsif supported_ruby
          raise
        end
      end
      puts 'dependency validation ok'
    RUBY
    expect(status).to be_success, output
    expect(output).to include('dependency validation ok')
    expect(output).not_to include('Scheduler should implement #fiber_interrupt')
  end
end
