require 'thor'

module GoodJob
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    desc :start, "Start jobs"
    def start
      require RAILS_ENVIRONMENT_RB

      GoodJob::Scheduler.new

      Kernel.loop do
        sleep 1
      end
    end

    default_task :start
  end
end
