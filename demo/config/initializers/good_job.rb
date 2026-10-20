Rails.application.configure do
  config.good_job.enable_pauses = true

  # Cron is configured in every environment so the dashboard shows it,
  # but entries only run by default in the demo (or with CRON_ENABLED_BY_DEFAULT);
  # enable them through the dashboard elsewhere.
  # Cron procs must be shareable for GoodJob.ractorize! (Ruby 4+)
  shareable = defined?(Ractor) && Ractor.respond_to?(:shareable_lambda) ? ->(&block) { Ractor.shareable_lambda(&block) } : ->(&block) { block }

  enabled_in_demo = shareable.call { Rails.env.demo? || ActiveModel::Type::Boolean.new.cast(ENV.fetch("CRON_ENABLED_BY_DEFAULT", nil)) }
  config.good_job.cron = {
    example: {
      description: "Enqueue an ExampleJob with a random sample of configuration",
      cron: "* * * * * *",
      class: "ExampleJob",
      args: (shareable.call do
        [ExampleJob::TYPES.sample.to_s]
      end),
      set: (shareable.call do
        queue = [:default, :elephants, :mice].sample
        delay = [0, (0..60).to_a.sample].sample
        priority = [-10, 0, 10].sample

        { wait: delay, queue: queue, priority: priority }
      end),
      enabled_by_default: enabled_in_demo,
    },
    other_example: {
      description: "Enqueue an OtherJob occasionally",
      cron: "*/15 * * * * *",
      class: "OtherJob",
      set: { queue: :default },
      enabled_by_default: enabled_in_demo,
    },
    batch_example: {
      description: "Enqueue a Batch",
      cron: "*/30 * * * * *",
      class: "ExampleJob::BatchJob",
      enabled_by_default: enabled_in_demo,
    },
    concurrency_example: {
      description: "Enqueue slow jobs that contend for a concurrency limit",
      cron: "*/30 * * * * *",
      class: "ExampleJob::ConcurrencyExampleJob",
      enabled_by_default: enabled_in_demo,
    },
    complex_schedule: {
      cron: shareable.call { |last_ran| last_ran ? last_ran + 17.hours : Time.now },
      class: "OtherJob",
      enabled_by_default: enabled_in_demo,
    },
    pg_hero_maintenance: {
      cron: "*/10 * * * *", # Every 10 minutes
      class: "PgHeroMaintenanceJob",
      description: "Runs PG Hero maintenance",
      enabled_by_default: enabled_in_demo,
    },
  }
end

Rails.configuration.after_initialize do
  # TODO: It should not be necessary to manually initialize Active Record base
  #   This seemed to be introduced when PG Hero was added.
  ActiveJob::Base
end

case Rails.env
when 'development'
  GoodJob.on_thread_error = -> (error) { Rails.logger.warn("#{error}\n#{error.backtrace}") }

  Rails.application.configure do
    config.good_job.enable_cron = ActiveModel::Type::Boolean.new.cast(ENV.fetch('GOOD_JOB_ENABLE_CRON', true))
  end
when 'test'
  # Exercised by spec/integration/supervisor_spec.rb to prove cluster lifecycle
  # hooks fire in the right process. Writes to $stdout (not GoodJob.logger, which
  # in test is the test.log Rails logger) so ShellOut can observe the output.
  if ActiveModel::Type::Boolean.new.cast(ENV['GOOD_JOB_TEST_LIFECYCLE_HOOKS'])
    GoodJob.before_supervisor_fork { $stdout.puts "[test hook] before_supervisor_fork PID=#{Process.pid}" }
    GoodJob.before_subprocess_boot { $stdout.puts "[test hook] before_subprocess_boot PID=#{Process.pid}" }
  end

  # Holds each subprocess inside its boot hook so a spec can deterministically
  # signal the supervisor while its subprocesses are still booting.
  if (subprocess_boot_delay = ENV['GOOD_JOB_TEST_SUBPROCESS_BOOT_DELAY'].presence)
    GoodJob.before_subprocess_boot do
      $stdout.puts "[test hook] subprocess_boot_delay PID=#{Process.pid}"
      sleep subprocess_boot_delay.to_f
    end
  end
when 'demo'
  Rails.application.configure do
    config.good_job.execution_mode = :async
    config.good_job.poll_interval = 30
    config.good_job.enable_cron = true
  end
when 'production'
  # production
else
  raise "Unconfigured environment for GoodJob"
end
