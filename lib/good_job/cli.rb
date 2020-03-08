require 'thor'

module GoodJob
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    desc :start, "Start jobs"
    def start
      require RAILS_ENVIRONMENT_RB

      scheduler = GoodJob::Scheduler.new

      %w[INT TERM].each do |signal|
        trap(signal) { @stop_good_job_executable = true }
      end
      @stop_good_job_executable = false

      $stdout.puts "GoodJob waiting for jobs..."

      Kernel.loop do
        sleep 0.1
        break if @stop_good_job_executable || scheduler.shutdown?
      end

      $stdout.puts "\nFinishing GoodJob's current jobs before exiting..."
      scheduler.shutdown
      $stdout.puts "GoodJob's jobs finished, exiting..."
    end

    default_task :start
  end
end
