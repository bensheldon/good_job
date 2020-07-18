require 'thor'

module GoodJob
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    desc :start, "Start job worker"
    method_option :max_threads,
                  type: :numeric,
                  desc: "Maximum number of threads to use for working jobs (default: ActiveRecord::Base.connection_pool.size)"
    method_option :queues,
                  type: :string,
                  banner: "queue1,queue2",
                  desc: "Queues to work from. Separate multiple queues with commas (default: *)"
    method_option :poll_interval,
                  type: :numeric,
                  desc: "Interval between polls for available jobs in seconds (default: 1)"
    def start
      require RAILS_ENVIRONMENT_RB

      max_threads = (
        options[:max_threads] ||
        ENV['GOOD_JOB_MAX_THREADS'] ||
        ENV['RAILS_MAX_THREADS'] ||
        ActiveRecord::Base.connection_pool.size
      ).to_i

      queue_names = (
        options[:queues] ||
        ENV['GOOD_JOB_QUEUES'] ||
        '*'
      ).split(',').map(&:strip)

      poll_interval = (
        options[:poll_interval] ||
        ENV['GOOD_JOB_POLL_INTERVAL']
      ).to_i

      job_query = GoodJob::Job.all.priority_ordered
      queue_names_without_all = queue_names.reject { |q| q == '*' }
      job_query = job_query.where(queue_name: queue_names_without_all) unless queue_names_without_all.size.zero?

      job_performer = job_query.to_performer

      $stdout.puts "GoodJob worker starting with max_threads=#{max_threads} on queues=#{queue_names.join(',')}"

      timer_options = {}
      timer_options[:execution_interval] = poll_interval if poll_interval.positive?

      pool_options = {
        max_threads: max_threads,
      }

      scheduler = GoodJob::Scheduler.new(job_performer, timer_options: timer_options, pool_options: pool_options)

      @stop_good_job_executable = false
      %w[INT TERM].each do |signal|
        trap(signal) { @stop_good_job_executable = true }
      end

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
