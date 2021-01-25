require 'rails_helper'

RSpec.describe 'Server modes', skip_if_java: true do
  context 'when development async' do
    it 'successfully starts the server' do
      env = {
        "RAILS_ENV" => "development",
        "GOOD_JOB_EXECUTION_MODE" => "async",
      }

      ShellOut.command('bundle exec rails s', env: env) do |shell|
        wait_until(max: 30) do
          expect(shell.output).to include(/Listening on/)
        end
      end
    end
  end

  context 'when production async' do
    it 'successfully runs' do
      env = {
        "RAILS_ENV" => "production",
        "GOOD_JOB_EXECUTION_MODE" => "async",
      }
      ShellOut.command('bundle exec rails s', env: env) do |shell|
        wait_until(max: 30) do
          expect(shell.output).to include(/GoodJob started scheduler/)
        end
      end
    end
  end
end
