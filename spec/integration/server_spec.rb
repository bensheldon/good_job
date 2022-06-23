# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Server modes', skip_if_java: true do
  let(:port) { 3009 }
  let(:pidfile) { Rails.root.join('tmp/pids/test_server.pid') }

  context 'when development async' do
    it 'successfully runs in the server' do
      env = {
        "RAILS_ENV" => "development",
        "GOOD_JOB_EXECUTION_MODE" => "async",
        "GOOD_JOB_ENABLE_CRON" => "true",
      }

      ShellOut.command("bundle exec rails s -p #{port} -P #{pidfile}", env: env) do |shell|
        wait_until(max: 30) do
          expect(shell.output).to include(/Listening on/)
          # In development, GoodJob starts up before Puma redirects logs to stdout
          expect(shell.output).to include(/Enqueued ExampleJob/)
        end
      end
    end
  end

  context 'when production async' do
    it 'successfully runs in the server' do
      env = {
        "RAILS_ENV" => "production",
        "GOOD_JOB_EXECUTION_MODE" => "async",
        "GOOD_JOB_ENABLE_CRON" => "true",
      }
      ShellOut.command("bundle exec rails s -p #{port} -P #{pidfile}", env: env) do |shell|
        wait_until(max: 30) do
          expect(shell.output).to include(/Listening on/)
          expect(shell.output).to include(/GoodJob started scheduler/)
          expect(shell.output).to include(/GoodJob started cron/)
        end
      end
    end

    it 'does not start GoodJob when running other commands' do
      env = {
        "RAILS_ENV" => "production",
        "GOOD_JOB_EXECUTION_MODE" => "async",
      }
      ShellOut.command('bundle exec rails db:version', env: env) do |shell|
        wait_until(max: 30) do
          expect(shell.output).to include(/Current version/)
        end
        expect(shell.output).not_to include(/GoodJob started scheduler/)
      end
    end
  end
end
