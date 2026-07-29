# frozen_string_literal: true

require 'rails_helper'
require 'net/http'
require 'uri'

# Boots a real supervisor and its subprocesses via the +good_job+ executable
# and asserts on the structured log output. Following Puma's integration-test
# approach, every wait polls with a deadline (via +wait_until+) rather than
# sleeping for a fixed time, which keeps the specs deterministic.
RSpec.describe 'Cluster mode', :skip_if_java do
  let(:env) do
    {
      "RAILS_ENV" => "test",
      "GOOD_JOB_SUBPROCESSES" => "2",
      "GOOD_JOB_MAX_THREADS" => "1",
      "GOOD_JOB_POLL_INTERVAL" => "30",
      "GOOD_JOB_SHUTDOWN_TIMEOUT" => "5",
      # macOS forbids calling into some system libraries (e.g. libpq) after
      # fork(); this env var relaxes that. It is a no-op on Linux (CI), but lets
      # the suite run on a developer's Mac.
      "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES",
    }
  end

  # @return [Array<Integer>] the OS PIDs of subprocesses that have booted, parsed from the log.
  def booted_subprocess_pids(output)
    output.join.scan(/started subprocess \(PID: (\d+)\)/).flatten.map(&:to_i).uniq
  end

  # @return [Integer] the PID of a subprocess's parent, i.e. the supervisor.
  def supervisor_pid_for(subprocess_pid)
    `ps -o ppid= -p #{subprocess_pid}`.strip.to_i
  end

  # @return [String] the process title (command) shown by `ps` for a PID.
  def process_title(pid)
    `ps -o command= -p #{pid}`.strip
  end

  it 'sets descriptive process titles for the supervisor and its subprocesses' do
    ShellOut.command("bundle exec good_job start", env: env) do |shell|
      pids = nil
      wait_until(max: 30, increments_of: 0.5) do
        pids = booted_subprocess_pids(shell.output)
        expect(pids.size).to eq(2)
      end

      expect(process_title(pids.first)).to include("good_job subprocess")
      expect(process_title(supervisor_pid_for(pids.first))).to include("good_job supervisor")
    end
  end

  it 'forks and boots the configured number of subprocesses' do
    ShellOut.command("bundle exec good_job start", env: env) do |shell|
      wait_until(max: 30, increments_of: 0.5) do
        expect(shell.output).to include(/started supervisor with subprocesses=2/)
        expect(booted_subprocess_pids(shell.output).size).to eq(2)
      end
    end
  end

  it 'replaces a subprocess that exits unexpectedly' do
    ShellOut.command("bundle exec good_job start", env: env) do |shell|
      original_pids = nil
      wait_until(max: 30, increments_of: 0.5) do
        original_pids = booted_subprocess_pids(shell.output)
        expect(original_pids.size).to eq(2)
      end

      Process.kill("TERM", original_pids.first)

      wait_until(max: 30, increments_of: 0.5) do
        # A subprocess with a PID not in the original set has since booted.
        expect(booted_subprocess_pids(shell.output) - original_pids).not_to be_empty
      end
    end
  end

  it 'forks one subprocess per pipe-delimited queue pool, each with its own queues and threads' do
    queues_env = env.merge("GOOD_JOB_QUEUES" => "elephant:2|mice:3").except("GOOD_JOB_SUBPROCESSES", "GOOD_JOB_MAX_THREADS")
    ShellOut.command("bundle exec good_job start", env: queues_env) do |shell|
      wait_until(max: 30, increments_of: 0.5) do
        expect(booted_subprocess_pids(shell.output).size).to eq(2)
        expect(shell.output.join).to include("started scheduler with queues=elephant max_threads=2")
        expect(shell.output.join).to include("started scheduler with queues=mice max_threads=3")
      end
    end
  end

  it 'runs lifecycle hooks in the supervisor and in each subprocess' do
    ShellOut.command("bundle exec good_job start", env: env.merge("GOOD_JOB_TEST_LIFECYCLE_HOOKS" => "true")) do |shell|
      wait_until(max: 30, increments_of: 0.5) do
        # before_supervisor_fork runs in the supervisor before every fork (so once
        # per subprocess at boot); before_subprocess_boot runs once per subprocess.
        expect(shell.output.join.scan('before_supervisor_fork PID=').size).to eq(2)
        expect(shell.output.join.scan('before_subprocess_boot PID=').size).to eq(2)
      end
    end
  end

  it 'serves cluster health checks on the probe port from the supervisor' do
    port = 7005
    ShellOut.command("bundle exec good_job start", env: env.merge("GOOD_JOB_PROBE_PORT" => port.to_s)) do |shell|
      wait_until(max: 30, increments_of: 0.5) do
        expect(booted_subprocess_pids(shell.output).size).to eq(2)
      end

      wait_until(max: 30, increments_of: 0.5) do
        response = begin
          Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/status/started"))
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::ReadTimeout, EOFError
          nil # probe server still binding
        end
        expect(response&.code).to eq("200")
      end

      expect(Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/status")).code).to eq("200")

      # /status/connected flips to 200 only once each subprocess has heartbeated
      # that its scheduler is running and its notifier is connected.
      wait_until(max: 30, increments_of: 0.5) do
        expect(Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/status/connected")).code).to eq("200")
      end
    end
  end

  it 'gracefully shuts its subprocesses down when it is terminated' do
    ShellOut.command("bundle exec good_job start", env: env) do |shell|
      pids = nil
      wait_until(max: 30, increments_of: 0.5) do
        pids = booted_subprocess_pids(shell.output)
        expect(pids.size).to eq(2)
      end

      Process.kill("TERM", supervisor_pid_for(pids.first))

      wait_until(max: 30, increments_of: 0.5) do
        expect(shell.output).to include(/shutting down subprocess/)
        expect(shell.output).to include(/shutting down scheduler/)
        expect(shell.output).to include(/supervisor is shut down/)
      end
    end
  end
end
