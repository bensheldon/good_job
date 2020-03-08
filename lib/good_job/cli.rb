require 'thor'

module GoodJob
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    desc :start, "Start jobs"
    method_option :max_threads, type: :numeric
    def start
      require RAILS_ENVIRONMENT_RB

      max_threads = options[:max_threads] ||
                    ENV['GOOD_JOB_MAX_THREADS'] ||
                    ENV['RAILS_MAX_THREADS'] ||
                    ActiveRecord::Base.connection_pool.size

      $stdout.puts "GoodJob starting with max_threads=#{max_threads}"
      scheduler = GoodJob::Scheduler.new(pool_options: { max_threads: max_threads })

      %w[INT TERM].each do |signal|
        trap(signal) { @stop_good_job_executable = true }
      end
      @stop_good_job_executable = false

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
