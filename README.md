# GoodJob

[![Gem Version](https://badge.fury.io/rb/good_job.svg)](https://rubygems.org/gems/good_job)
[![Test Status](https://github.com/bensheldon/good_job/workflows/Test/badge.svg)](https://github.com/bensheldon/good_job/actions)
[![Ruby Toolbox](https://img.shields.io/badge/dynamic/json?color=blue&label=Ruby%20Toolbox&query=%24.projects%5B0%5D.score&url=https%3A%2F%2Fwww.ruby-toolbox.com%2Fapi%2Fprojects%2Fcompare%2Fgood_job&logo=data:image/svg+xml;base64,PHN2ZyBhcmlhLWhpZGRlbj0idHJ1ZSIgZm9jdXNhYmxlPSJmYWxzZSIgZGF0YS1wcmVmaXg9ImZhcyIgZGF0YS1pY29uPSJmbGFzayIgY2xhc3M9InN2Zy1pbmxpbmUtLWZhIGZhLWZsYXNrIGZhLXctMTQiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB2aWV3Qm94PSIwIDAgNDQ4IDUxMiI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik00MzcuMiA0MDMuNUwzMjAgMjE1VjY0aDhjMTMuMyAwIDI0LTEwLjcgMjQtMjRWMjRjMC0xMy4zLTEwLjctMjQtMjQtMjRIMTIwYy0xMy4zIDAtMjQgMTAuNy0yNCAyNHYxNmMwIDEzLjMgMTAuNyAyNCAyNCAyNGg4djE1MUwxMC44IDQwMy41Qy0xOC41IDQ1MC42IDE1LjMgNTEyIDcwLjkgNTEyaDMwNi4yYzU1LjcgMCA4OS40LTYxLjUgNjAuMS0xMDguNXpNMTM3LjkgMzIwbDQ4LjItNzcuNmMzLjctNS4yIDUuOC0xMS42IDUuOC0xOC40VjY0aDY0djE2MGMwIDYuOSAyLjIgMTMuMiA1LjggMTguNGw0OC4yIDc3LjZoLTE3MnoiPjwvcGF0aD48L3N2Zz4=)](https://www.ruby-toolbox.com/projects/good_job)

GoodJob is a multithreaded, Postgres-based, ActiveJob backend for Ruby on Rails.

**Inspired by [Delayed::Job](https://github.com/collectiveidea/delayed_job) and [Que](https://github.com/que-rb/que), GoodJob is designed for maximum compatibility with Ruby on Rails, ActiveJob, and Postgres to be simple and performant for most workloads.**

- **Designed for ActiveJob.** Complete support for [async, queues, delays, priorities, timeouts, and retries](https://edgeguides.rubyonrails.org/active_job_basics.html) with near-zero configuration.
- **Built for Rails.** Fully adopts Ruby on Rails [threading and code execution guidelines](https://guides.rubyonrails.org/threading_and_code_execution.html) with [Concurrent::Ruby](https://github.com/ruby-concurrency/concurrent-ruby).
- **Backed by Postgres.** Relies upon Postgres integrity, session-level Advisory Locks to provide run-once safety and stay within the limits of `schema.rb`, and LISTEN/NOTIFY to reduce queuing latency.
- **For most workloads.** Targets full-stack teams, economy-minded solo developers, and applications that enqueue 1-million jobs/day and more.

For more of the story of GoodJob, read the [introductory blog post](https://island94.org/2020/07/introducing-goodjob-1-0).

<details markdown="1">
<summary><strong>📊 Comparison of GoodJob with other job queue backends (click to expand)</strong></summary>

|                 | Queues, priority, retries | Database                              | Concurrency       | Reliability/Integrity  | Latency                  |
|-----------------|---------------------------|---------------------------------------|-------------------|------------------------|--------------------------|
| **GoodJob**     | ✅ Yes                     | ✅ Postgres                            | ✅ Multithreaded   | ✅ ACID, Advisory Locks | ✅ Postgres LISTEN/NOTIFY |
| **Que**         | ✅ Yes                     | 🔶️ Postgres, requires  `structure.sql` | ✅ Multithreaded   | ✅ ACID, Advisory Locks | ✅ Postgres LISTEN/NOTIFY |
| **Delayed Job** | ✅ Yes                     | ✅ Postgres                            | 🔴 Single-threaded | ✅ ACID, record-based   | 🔶 Polling                |
| **Sidekiq**     | ✅ Yes                     | 🔴 Redis                               | ✅ Multithreaded   | 🔴 Crashes lose jobs    | ✅ Redis BRPOP            |
| **Sidekiq Pro** | ✅ Yes                     | 🔴 Redis                               | ✅ Multithreaded   | ✅ Redis RPOPLPUSH      | ✅ Redis RPOPLPUSH        |

</details>

## Table of contents

- [Set up](#set-up)
- [Compatibility](#compatibility)
- [Configuration](#configuration)
    - [Command-line options](#command-line-options)
        - [`good_job start`](#good_job-start)
        - [`good_job cleanup_preserved_jobs`](#good_job-cleanup_preserved_jobs)
    - [Configuration options](#configuration-options)
    - [Global options](#global-options)
    - [Dashboard](#dashboard)
    - [ActiveJob concurrency](#activejob-concurrency)
    - [Cron-style repeating/recurring jobs](#cron-style-repeatingrecurring-jobs)
    - [Updating](#updating)
        - [Upgrading minor versions](#upgrading-minor-versions)
        - [Upgrading v1 to v2](#upgrading-v1-to-v2)
- [Go deeper](#go-deeper)
    - [Exceptions, retries, and reliability](#exceptions-retries-and-reliability)
        - [Exceptions](#exceptions)
        - [Retries](#retries)
        - [ActionMailer retries](#actionmailer-retries)
    - [Timeouts](#timeouts)
    - [Optimize queues, threads, and processes](#optimize-queues-threads-and-processes)
    - [Database connections](#database-connections)
        - [Production setup](#production-setup)
    - [Execute jobs async / in-process](#execute-jobs-async--in-process)
    - [Migrate to GoodJob from a different ActiveJob backend](#migrate-to-goodjob-from-a-different-activejob-backend)
    - [Monitor and preserve worked jobs](#monitor-and-preserve-worked-jobs)
    - [PgBouncer compatibility](#pgbouncer-compatibility)
    - [CLI HTTP health check probes](#cli-http-health-check-probes)
- [Contribute](#contribute)
    - [Gem development](#gem-development)
    - [Release](#release)
- [License](#license)

## Set up

1. Add `good_job` to your application's Gemfile and install the gem:

    ```sh
    bundle add good_job
    ```

1. Run the GoodJob install generator. This will generate a database migration to create a table for GoodJob's job records:

    ```bash
    bin/rails g good_job:install
    ```

    Run the migration:

    ```bash
    bin/rails db:migrate
    ```

   Optional: If using Rails' multiple databases with the `migrations_paths` configuration option, use the `--database` option:

    ```bash
    bin/rails g good_job:install --database animals
    bin/rails db:migrate:animals
    ```

1. Configure the ActiveJob adapter:

    ```ruby
    # config/application.rb or config/environments/{RAILS_ENV}.rb
    config.active_job.queue_adapter = :good_job
    ```

1. Inside of your application, queue your job 🎉:

    ```ruby
    YourJob.perform_later
    ```

    GoodJob supports all ActiveJob features:

    ```ruby
    YourJob.set(queue: :some_queue, wait: 5.minutes, priority: 10).perform_later
    ```

1. In development, GoodJob executes jobs immediately. In production, GoodJob provides different options:

    - By default, GoodJob separates job enqueuing from job execution so that jobs can be scaled independently of the web server.  Use the GoodJob command-line tool to execute jobs:

        ```bash
        bundle exec good_job start
        ```

        Ideally the command-line tool should be run on a separate machine or container from the web process. For example, on Heroku:

        ```Procfile
        web: rails server
        worker: bundle exec good_job start
        ```

        The command-line tool supports a variety of options, see the reference below for command-line configuration.

    - GoodJob can also be configured to execute jobs within the web server process to save on resources. This is useful for low-workloads when economy is paramount.

        ```bash
        GOOD_JOB_EXECUTION_MODE=async rails server
        ```

        Additional configuration is likely necessary, see the reference below for configuration.

## Compatibility

- **Ruby on Rails:** 5.2+
- **Ruby:** MRI 2.5+. JRuby 9.2.13+
- **Postgres:** 9.6+

## Configuration

### Command-line options

There several top-level commands available through the `good_job` command-line tool.

Configuration options are available with `help`.

#### `good_job start`

`good_job start` executes queued jobs.

```bash
$ bundle exec good_job help start

Usage:
  good_job start

Options:
  [--queues=QUEUE_LIST]        # Queues or pools to work from. (env var: GOOD_JOB_QUEUES, default: *)
  [--max-threads=COUNT]        # Default number of threads per pool to use for working jobs. (env var: GOOD_JOB_MAX_THREADS, default: 5)
  [--poll-interval=SECONDS]    # Interval between polls for available jobs in seconds (env var: GOOD_JOB_POLL_INTERVAL, default: 1)
  [--max-cache=COUNT]          # Maximum number of scheduled jobs to cache in memory (env var: GOOD_JOB_MAX_CACHE, default: 10000)
  [--shutdown-timeout=SECONDS] # Number of seconds to wait for jobs to finish when shutting down before stopping the thread. (env var: GOOD_JOB_SHUTDOWN_TIMEOUT, default: -1 (forever))
  [--enable-cron]              # Whether to run cron process (default: false)
  [--daemonize]                # Run as a background daemon (default: false)
  [--pidfile=PIDFILE]          # Path to write daemonized Process ID (env var: GOOD_JOB_PIDFILE, default: tmp/pids/good_job.pid)
  [--probe-port=PORT]          # Port for http health check (env var: GOOD_JOB_PROBE_PORT, default: nil)

Executes queued jobs.

All options can be configured with environment variables.
See option descriptions for the matching environment variable name.

== Configuring queues

Separate multiple queues with commas; exclude queues with a leading minus;
separate isolated execution pools with semicolons and threads with colons.
```

#### `good_job cleanup_preserved_jobs`

`good_job cleanup_preserved_jobs` deletes preserved job records. See `GoodJob.preserve_job_records` for when this command is useful.

```bash
$ bundle exec good_job help cleanup_preserved_jobs

Usage:
  good_job cleanup_preserved_jobs

Options:
  [--before-seconds-ago=SECONDS] # Delete records finished more than this many seconds ago (env var:  GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO, default: 86400)

Deletes preserved job records.

By default, GoodJob deletes job records when the job is performed and this
command is not necessary.

However, when `GoodJob.preserve_job_records = true`, the jobs will be
preserved in the database. This is useful when wanting to analyze or
inspect job performance.

If you are preserving job records this way, use this command regularly
to delete old records and preserve space in your database.
```

### Configuration options

ActiveJob configuration depends on where the code is placed:

- `config.active_job.queue_adapter = :good_job` within `config/application.rb` or `config/environments/*.rb`.
- `ActiveJob::Base.queue_adapter = :good_job` within an initializer (e.g. `config/initializers/active_job.rb`).

GoodJob configuration can be placed within Rails `config` directory for all environments (`config/application.rb`), within a particular environment (e.g. `config/environments/development.rb`), or within an initializer (e.g. `config/initializers/good_job.rb`).

Configuration examples:

```ruby
Rails.application.configure do
  # Configure options individually...
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = false
  config.good_job.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
  config.good_job.execution_mode = :async
  config.good_job.queues = '*'
  config.good_job.max_threads = 5
  config.good_job.poll_interval = 30 # seconds
  config.good_job.shutdown_timeout = 25 # seconds
  config.good_job.enable_cron = true
  config.good_job.cron = { example: { cron: '0 * * * *', class: 'ExampleJob'  } }

  # ...or all at once.
  config.good_job = {
    preserve_job_records: true,
    retry_on_unhandled_error: false,
    on_thread_error: -> (exception) { Raven.capture_exception(exception) },
    execution_mode: :async,
    queues: '*',
    max_threads: 5,
    poll_interval: 30,
    shutdown_timeout: 25,
    enable_cron: true,
    cron: {
      example: {
        cron: '0 * * * *',
        class: 'ExampleJob'
      },
    },
  }
end
```

Available configuration options are:

- `execution_mode` (symbol) specifies how and where jobs should be executed. You can also set this with the environment variable `GOOD_JOB_EXECUTION_MODE`. It can be any one of:
    - `:inline` executes jobs immediately in whatever process queued them (usually the web server process). This should only be used in test and development environments.
    - `:external` causes the adapter to enqueue jobs, but not execute them. When using this option (the default for production environments), you’ll need to use the command-line tool to actually execute your jobs.
    - `:async` (or `:async_server`) executes jobs in separate threads within the Rails web server process (`bundle exec rails server`). It can be more economical for small workloads because you don’t need a separate machine or environment for running your jobs, but if your web server is under heavy load or your jobs require a lot of resources, you should choose `:external` instead.  When not in the Rails web server, jobs will execute in `:external` mode to ensure jobs are not executed within `rails console`, `rails db:migrate`, `rails assets:prepare`, etc.
    - `:async_all` executes jobs in separate threads in _any_ Rails process.
- `queues` (string) sets queues or pools to execute jobs. You can also set this with the environment variable `GOOD_JOB_QUEUES`.
- `max_threads` (integer) sets the default number of threads per pool to use for working jobs. You can also set this with the environment variable `GOOD_JOB_MAX_THREADS`.
- `poll_interval` (integer) sets the number of seconds between polls for jobs when `execution_mode` is set to `:async`. You can also set this with the environment variable `GOOD_JOB_POLL_INTERVAL`. A poll interval of `-1` disables polling completely.
- `max_cache` (integer) sets the maximum number of scheduled jobs that will be stored in memory to reduce execution latency when also polling for scheduled jobs. Caching 10,000 scheduled jobs uses approximately 20MB of memory. You can also set this with the environment variable `GOOD_JOB_MAX_CACHE`.
- `shutdown_timeout` (float) number of seconds to wait for jobs to finish when shutting down before stopping the thread. Defaults to forever: `-1`. You can also set this with the environment variable `GOOD_JOB_SHUTDOWN_TIMEOUT`.
- `enable_cron` (boolean) whether to run cron process. Defaults to `false`. You can also set this with the environment variable `GOOD_JOB_ENABLE_CRON`.
- `cron` (hash) cron configuration. Defaults to `{}`. You can also set this as a JSON string with the environment variable `GOOD_JOB_CRON`
- `cleanup_preserved_jobs_before_seconds_ago` (integer) number of seconds to preserve jobs when using the `$ good_job cleanup_preserved_jobs` CLI command or calling `GoodJob.cleanup_preserved_jobs`. Defaults to `86400` (1 day). Can also be set with  the environment variable `GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO`.  _This configuration is only used when {GoodJob.preserve_job_records} is `true`._
- `cleanup_interval_jobs` (integer) Number of jobs a Scheduler will execute before cleaning up preserved jobs. Defaults to `nil`. Can also be set with  the environment variable `GOOD_JOB_CLEANUP_INTERVAL_JOBS`.
- `cleanup_interval_seconds` (integer) Number of seconds a Scheduler will wait before cleaning up preserved jobs. Defaults to `nil`. Can also be set with  the environment variable `GOOD_JOB_CLEANUP_INTERVAL_SECONDS`.
- `logger` ([Rails Logger](https://api.rubyonrails.org/classes/ActiveSupport/Logger.html)) lets you set a custom logger for GoodJob. It should be an instance of a Rails `Logger` (Default: `Rails.logger`).
- `preserve_job_records` (boolean) keeps job records in your database even after jobs are completed. (Default: `false`)
- `retry_on_unhandled_error` (boolean) causes jobs to be re-queued and retried if they raise an instance of `StandardError`. Be advised this may lead to jobs being repeated infinitely ([see below for more on retries](#retries)). Instances of `Exception`, like SIGINT, will *always* be retried, regardless of this attribute’s value. (Default: `true`)
- `on_thread_error` (proc, lambda, or callable) will be called when an Exception. It can be useful for logging errors to bug tracking services, like Sentry or Airbrake. Example:

    ```ruby
    config.good_job.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
    ```

By default, GoodJob configures the following execution modes per environment:

```ruby

# config/environments/development.rb
config.active_job.queue_adapter = :good_job
config.good_job.execution_mode = :async

# config/environments/test.rb
config.active_job.queue_adapter = :good_job
config.good_job.execution_mode = :inline

# config/environments/production.rb
config.active_job.queue_adapter = :good_job
config.good_job.execution_mode = :external
```

### Global options

Good Job’s general behavior can also be configured via attributes directly on the `GoodJob` module:

- **`GoodJob.active_record_parent_class`** (string) The ActiveRecord parent class inherited by GoodJob's ActiveRecord model `GoodJob::Job` (defaults to `"ActiveRecord::Base"`). Configure this when using [multiple databases with ActiveRecord](https://guides.rubyonrails.org/active_record_multiple_databases.html) or when other custom configuration is necessary for the ActiveRecord model to connect to the Postgres database. _The value must be a String to avoid premature initialization of ActiveRecord._
- **`GoodJob.logger`** ([Rails Logger](https://api.rubyonrails.org/classes/ActiveSupport/Logger.html)) lets you set a custom logger for GoodJob. It should be an instance of a Rails `Logger`.
- **`GoodJob.preserve_job_records`** (boolean) keeps job records in your database even after jobs are completed. (Default: `false`)
- **`GoodJob.retry_on_unhandled_error`** (boolean) causes jobs to be re-queued and retried if they raise an instance of `StandardError`. Be advised this may lead to jobs being repeated infinitely ([see below for more on retries](#retries)). Instances of `Exception`, like SIGINT, will *always* be retried, regardless of this attribute’s value. (Default: `true`)
- **`GoodJob.on_thread_error`** (proc, lambda, or callable) will be called when an Exception. It can be useful for logging errors to bug tracking services, like Sentry or Airbrake.

You’ll generally want to configure these in `config/initializers/good_job.rb`, like so:

```ruby
# config/initializers/good_job.rb
GoodJob.active_record_parent_class = "ApplicationRecord"
GoodJob.preserve_job_records = true
GoodJob.retry_on_unhandled_error = false
GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
```

### Dashboard

![Dashboard UI](https://github.com/bensheldon/good_job/raw/main/SCREENSHOT.png)

_🚧 GoodJob's dashboard is a work in progress. Please contribute ideas and code on [Github](https://github.com/bensheldon/good_job/issues)._

GoodJob includes a Dashboard as a mountable `Rails::Engine`.

1. Explicitly require the Engine code at the top of your `config/application.rb` file, immediately after Rails is required and before Bundler requires the Rails' groups. This is necessary because the mountable engine is an optional feature of GoodJob.

    ```ruby
    # config/application.rb
    require_relative 'boot'

    require 'rails/all'
    require 'good_job/engine' # <= Add this line
    # ...
    ```

   Note: If you find the dashboard fails to reload due to a routing error and uninitialized constant `GoodJob::ExecutionsController`, this is likely because you are not requiring the engine early enough.

1. Mount the engine in your `config/routes.rb` file. The following will mount it at `http://example.com/good_job`.

    ```ruby
    # config/routes.rb
    # ...
    mount GoodJob::Engine => 'good_job'
    ```

    Because jobs can potentially contain sensitive information, you should authorize access. For example, using Devise's `authenticate` helper, that might look like:

    ```ruby
    # config/routes.rb
    # ...
    authenticate :user, ->(user) { user.admin? } do
      mount GoodJob::Engine => 'good_job'
    end
    ```

    Another option is using basic auth like this:

    ```ruby
    # config/initializers/good_job.rb
    GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(Rails.application.credentials.good_job_username, username) &&
        ActiveSupport::SecurityUtils.secure_compare(Rails.application.credentials.good_job_password, password)
    end
    ```

#### Live Polling

The Dashboard can be set to automatically refresh by checking "Live Poll" in the Dashboard header, or by setting `?poll=10` with the interval in seconds (default 30 seconds).

### ActiveJob concurrency

GoodJob can extend ActiveJob to provide limits on concurrently running jobs, either at time of _enqueue_ or at _perform_. Limiting concurrency can help prevent duplicate, double or unecessary jobs from being enqueued, or race conditions when performing, for example when interacting with 3rd-party APIs.

**Note:** Limiting concurrency at _enqueue_ requires Rails 6.0+ because Rails 5.2 cannot halt ActiveJob callbacks.

```ruby
class MyJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    # Maximum number of unfinished jobs to allow with the concurrency key
    total_limit: 1,

    # Or, if more control is needed:
    # Maximum number of jobs with the concurrency key to be
    # concurrently enqueued (excludes performing jobs)
    enqueue_limit: 2,

    # Maximum number of jobs with the concurrency key to be
    # concurrently performed (excludes enqueued jobs)
    perform_limit: 1,

    # Note: Under heavy load, the total number of jobs may exceed the
    # sum of `enqueue_limit` and `perform_limit` because of race conditions
    # caused by imperfectly disjunctive states. If you need to constrain
    # the total number of jobs, use `total_limit` instead. See #378.

    # A unique key to be globally locked against.
    # Can be String or Lambda/Proc that is invoked in the context of the job.
    # Note: Arguments passed to #perform_later can be accessed through ActiveJob's `arguments` method
    # which is an array containing positional arguments and, optionally, a kwarg hash.
    key: -> { "Unique-#{arguments.first}-#{arguments.last[:version]}" } #  MyJob.perform_later("Alice", version: 'v2') => "Unique-Alice-v2"
  )

  def perform(first_name)
    # do work
  end
end
```

When testing, the resulting concurrency key value can be inspected:

```ruby
job = MyJob.perform_later("Alice")
job.good_job_concurrency_key #=> "Unique-Alice"
```

### Cron-style repeating/recurring jobs

GoodJob can enqueue jobs on a recurring basis that can be used as a replacement for cron.

Cron-style jobs are run on every GoodJob process (e.g. CLI or `async` execution mode) when `config.good_job.enable_cron = true`, but GoodJob's cron uses unique indexes to ensure that only a single job is enqeued at the given time interval.

Cron-format is parsed by the [`fugit`](https://github.com/floraison/fugit) gem, which has support for seconds-level resolution (e.g. `* * * * * *`) and natural language parsing (e.g. `every second`).

```ruby
# config/environments/application.rb or a specific environment e.g. production.rb

# Enable cron in this process; e.g. only run on the first Heroku worker process
config.good_job.enable_cron = ENV['DYNO'] == 'worker.1' # or `true` or via $GOOD_JOB_ENABLE_CRON

# Configure cron with a hash that has a unique key for each recurring job
config.good_job.cron = {
  # Every 15 minutes, enqueue `ExampleJob.set(priority: -10).perform_later(42, name: "Alice")`
  frequent_task: { # each recurring job must have a unique key
    cron: "*/15 * * * *", # cron-style scheduling format by fugit gem
    class: "ExampleJob", # reference the Job class with a string
    args: [42, { name: "Alice" }], # arguments to pass; can also be a proc e.g. `-> { [{ when: Time.now }] }`
    set: { priority: -10 }, # additional ActiveJob properties; can also be a lambda/proc e.g. `-> { { priority: [1,2].sample } }`
    description: "Something helpful", # optional description that appears in Dashboard (coming soon!)
  },
  another_task: {
    cron: "0 0,12 * * *",
    class: "AnotherJob",
  },
  # etc.
}
```

### Updating

GoodJob follows semantic versioning, though updates may be encouraged through deprecation warnings in minor versions.

#### Upgrading minor versions

Upgrading between minor versions (e.g. v1.4 to v1.5) should not introduce breaking changes, but can introduce new deprecation warnings and database migration notices.

To perform upgrades to the GoodJob database tables:

1. Generate new database migration files:

    ```bash
    bin/rails g good_job:update
    ```

   Optional: If using Rails' multiple databases with the `migrations_paths` configuration option, use the `--database` option:

    ```bash
    bin/rails g good_job:update --database animals
    ```

1. Run the database migration locally

    ```bash
    bin/rails db:migrate
    ```

1. Commit the migration files and resulting `db/schema.rb` changes.
1. Deploy the code, run the migrations against the production database, and restart server/worker processes.

#### Upgrading v1 to v2

GoodJob v2 introduces a new Advisory Lock key format that is different than the v1 advisory lock key format; it's therefore necessary to perform a simple, but staged production upgrade. If you are already using `>= v1.12+` no other changes are necessary.

1. Upgrade your production environment to `v1.99.x` following the minor version upgrade process, including database migrations. `v1.99` is a transitional release that is safely compatible with both `v1.x` and `v2.0.0` because it uses both `v1`- and `v2`-formatted advisory locks.
1. Address any deprecation warnings generated by `v1.99`.
1. Upgrade your production environment to `v1.99.x` to `v2.0.x` again following the _minor_ upgrade process.

Notable changes:

- Renames `:async_server` execution mode to `:async`; renames prior `:async` execution mode to `:async_all`.
- Sets default Development environment's execution mode to `:async` with disabled polling.
- Excludes performing jobs from `enqueue_limit`'s count in `GoodJob::ActiveJobExtensions::Concurrency`.
- Triggers `GoodJob.on_thread_error` for unhandled ActiveJob exceptions.
- Renames `GoodJob.reperform_jobs_on_standard_error` accessor to `GoodJob.retry_on_unhandled_error`.
- Renames `GoodJob::Adapter.shutdown(wait:)` argument to `GoodJob::Adapter.shutdown(timeout:)`.
- Changes Advisory Lock key format from `good_jobs[ROW_ID]` to `good_jobs-[ACTIVE_JOB_ID]`.
- Expects presence of columns `good_jobs.active_job_id`, `good_jobs.concurrency_key`, `good_jobs.concurrency_key`, and `good_jobs.retried_good_job_id`.

## Go deeper

### Exceptions, retries, and reliability

GoodJob guarantees that a completely-performed job will run once and only once. GoodJob fully supports ActiveJob's built-in functionality for error handling, retries and timeouts.

#### Exceptions

ActiveJob provides [tools for rescuing and retrying exceptions](https://guides.rubyonrails.org/active_job_basics.html#exceptions), including `retry_on`, `discard_on`, `rescue_from` that will rescue exceptions before they get to GoodJob.

If errors do reach GoodJob, you can assign a callable to `GoodJob.on_thread_error` to be notified. For example, to log errors to an exception monitoring service like Sentry (or Bugsnag, Airbrake, Honeybadger, etc.):

```ruby
# config/initializers/good_job.rb
GoodJob.on_thread_error = -> (exception) { Raven.capture_exception(exception) }
```

#### Retries

By default, GoodJob will automatically and immediately retry a job when an exception is raised to GoodJob.

However, ActiveJob can be configured to retry an infinite number of times, with an exponential backoff. Using ActiveJob's `retry_on` prevents exceptions from reaching GoodJob:

```ruby
class ApplicationJob < ActiveJob::Base
  retry_on StandardError, wait: :exponentially_longer, attempts: Float::INFINITY
  # ...
end
```

When using `retry_on` with _a limited number of retries_, the final exception will not be rescued and will raise to GoodJob. GoodJob can be configured to discard un-handled exceptions instead of retrying them. Be aware that if NOT setting `retry_on_unhandled_error` to `false` good_job will by default retry the failing job and may do this infinitely without pause thereby at least causing high load. In most cases `retry_on_unhandled_error` should be set as following:

```ruby
# config/initializers/good_job.rb
GoodJob.retry_on_unhandled_error = false
```

Alternatively, pass a block to `retry_on` to handle the final exception instead of raising it to GoodJob:

```ruby
class ApplicationJob < ActiveJob::Base
  retry_on StandardError, attempts: 5 do |_job, _exception|
    # Log error, do nothing, etc.
  end
  # ...
end
```

When using `retry_on` with an infinite number of retries, exceptions will never be raised to GoodJob, which means `GoodJob.on_thread_error` will never be called. To report log or report exceptions to an exception monitoring service (e.g. Sentry, Bugsnag, Airbrake, Honeybadger, etc), create an explicit exception wrapper. For example:

```ruby
class ApplicationJob < ActiveJob::Base
  retry_on StandardError, wait: :exponentially_longer, attempts: Float::INFINITY

  retry_on SpecialError, attempts: 5 do |_job, exception|
    Raven.capture_exception(exception)
  end

  around_perform do |_job, block|
    block.call
  rescue StandardError => e
    Raven.capture_exception(e)
    raise
  end
  # ...
end
```

#### ActionMailer retries

Any configuration in `ApplicationJob` will have to be duplicated on `ActionMailer::MailDeliveryJob` (`ActionMailer::DeliveryJob` in Rails 5.2 or earlier) because ActionMailer uses a custom class, `ActionMailer::MailDeliveryJob`, which inherits from `ActiveJob::Base`,  rather than your applications `ApplicationJob`.

You can use an initializer to configure `ActionMailer::MailDeliveryJob`, for example:

```ruby
# config/initializers/good_job.rb
ActionMailer::MailDeliveryJob.retry_on StandardError, wait: :exponentially_longer, attempts: Float::INFINITY

# With Sentry (or Bugsnag, Airbrake, Honeybadger, etc.)
ActionMailer::MailDeliveryJob.around_perform do |_job, block|
  block.call
rescue StandardError => e
  Raven.capture_exception(e)
  raise
end
```

Note, that `ActionMailer::MailDeliveryJob` is a default since Rails 6.0. Be sure that your app is using that class, as it
might also be configured to use (deprecated now) `ActionMailer::DeliveryJob`.

### Timeouts

Job timeouts can be configured with an `around_perform`:

```ruby
class ApplicationJob < ActiveJob::Base
  JobTimeoutError = Class.new(StandardError)

  around_perform do |_job, block|
    # Timeout jobs after 10 minutes
    Timeout.timeout(10.minutes, JobTimeoutError) do
      block.call
    end
  end
end
```

### Optimize queues, threads, and processes

By default, GoodJob creates a single thread execution pool that will execute jobs from any queue. Depending on your application's workload, job types, and service level objectives, you may wish to optimize execution resources. For example, providing dedicated execution resources for transactional emails so they are not delayed by long-running batch jobs. Some options:

- Multiple isolated execution pools within a single process:

    For moderate workloads, multiple isolated thread execution pools offers a good balance between congestion management and economy.

    A pool is configured with the following syntax `<participating_queues>:<thread_count>`:

    - `<participating_queues>`: either `queue1,queue2` (only those queues), `*` (all) or `-queue1,queue2` (all except those queues).
    - `<thread_count>`: a count overriding for this specific pool the global `max-threads`.

    Pool configurations are separated with a semicolon (;) in the `queues` configuration

    ```bash
    $ bundle exec good_job \
        --queues="transactional_messages:2;batch_processing:1;-transactional_messages,batch_processing:2;*" \
        --max-threads=5
    ```

    This configuration will result in a single process with 4 isolated thread execution pools.

    - `transactional_messages:2`: execute jobs enqueued on `transactional_messages`, with up to 2 threads.
    - `batch_processing:1` execute jobs enqueued on `batch_processing`, with a single thread.
    - `-transactional_messages,batch_processing`: execute jobs enqueued on _any_ queue _excluding_ `transactional_messages` or `batch_processing`, with up to 2 threads.
    - `*`: execute jobs on any queue, with up to 5 threads (as configured by `--max-threads=5`).

    Configuration can be injected by environment variables too:

    ```bash
    $ GOOD_JOB_QUEUES="transactional_messages:2;batch_processing:1;-transactional_messages,batch_processing:2;*" \
      GOOD_JOB_MAX_THREADS=5 \
      bundle exec good_job
    ```

- Multiple processes:

    While multiple isolated thread execution pools offer a way to provide dedicated execution resources, those resources are bound to a single machine. To scale them independently, define several processes.

    For example, this configuration on Heroku allows to customize the dyno count (instances), or type (CPU/RAM), per process type:

    ```procfile
    # Procfile

    # Separate process types
    worker: bundle exec good_job --max-threads=5
    transactional_worker: bundle exec good_job --queues="transactional_messages" --max-threads=2
    batch_worker: bundle exec good_job --queues="batch_processing" --max-threads=1
    ```

    To optimize for CPU performance at the expense of greater memory and system resource usage, while keeping a single process type (and thus a single dyno), combine several processes and wait for them:

    ```procfile
    # Procfile

    # Combined multi-process
    combined_worker: bundle exec good_job --max-threads=5 & bundle exec good_job --queues="transactional_messages" --max-threads=2 & bundle exec good_job --queues="batch_processing" --max-threads=1 & wait -n
    ```

Keep in mind, queue operations and management is an advanced discipline. This stuff is complex, especially for heavy workloads and unique processing requirements. Good job 👍

### Database connections

Each GoodJob execution thread requires its own database connection that is automatically checked out from Rails’ connection pool. For example:

```yaml
# config/database.yml
pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5).to_i + 3 + (ENV.fetch("GOOD_JOB_MAX_THREADS", 5).to_i %>
```

To calculate the total number of the database connections you'll need:

- 1 connection dedicated to the scheduler aka `LISTEN/NOTIFY`
- 1 connection per query pool thread e.g. `--queues=mice:2;elephants:1` is 3 threads. Pool thread size defaults to `--max-threads`
- (optional) 2 connections for Cron scheduler if you're running it
- (optional) 1 connection per subthread, if your application makes multithreaded database queries within a job
- When running `:async`, you must also add the number of threads by the webserver

The queue process will not crash if the connections pool is exhausted, instead it will report an exception (eg. `ActiveRecord::ConnectionTimeoutError`).

#### Production setup

When running GoodJob in a production environment, you should be mindful of:

- [Execution mode](execute-jobs-async--in-process)
- [Database connection pool size](#database-connections)
- [Health check probes](#cli-http-health-check-probes) and potentially the [instrumentation support](#monitor-and-preserve-worked-jobs)

The recommended way to monitor the queue in production is:

- have an exception notifier callback (see `on_thread_error`)
- if possible, run the queue as a dedicated instance and use available HTTP health check probes instead of pid-based monitoring
- keep an eye on the number of jobs in the queue (abnormal high number of unscheduled jobs means the queue could be underperforming)
- consider performance monitoring services which support the built-in Rails instrumentation (eg. Sentry, Skylight, etc.)

### Execute jobs async / in-process

GoodJob can execute jobs "async" in the same process as the web server (e.g. `bin/rails s`). GoodJob's async execution mode offers benefits of economy by not requiring a separate job worker process, but with the tradeoff of increased complexity. Async mode can be configured in two ways:

- Via Rails configuration:

    ```ruby
    # config/environments/production.rb
    config.active_job.queue_adapter = :good_job

    # To change the execution mode
    config.good_job.execution_mode = :async

    # Or with more configuration
    config.good_job = {
      execution_mode: :async,
      max_threads: 4,
      poll_interval: 30
    }
    ```

- Or, with environment variables:

    ```bash
    GOOD_JOB_EXECUTION_MODE=async GOOD_JOB_MAX_THREADS=4 GOOD_JOB_POLL_INTERVAL=30 bin/rails server
    ```

Depending on your application configuration, you may need to take additional steps:

- Ensure that you have enough database connections for both web and job execution threads:

    ```yaml
    # config/database.yml
    pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5).to_i + ENV.fetch("GOOD_JOB_MAX_THREADS", 4).to_i %>
    ```

- When running Puma with workers (`WEB_CONCURRENCY > 0`) or another process-forking web server, GoodJob's threadpool schedulers should be stopped before forking, restarted after fork, and cleanly shut down on exit. Stopping GoodJob's scheduler pre-fork is recommended to ensure that GoodJob does not continue executing jobs in the parent/controller process. For example, with Puma:

    ```ruby
    # config/puma.rb

    before_fork do
      GoodJob.shutdown
    end

    on_worker_boot do
      GoodJob.restart
    end

    on_worker_shutdown do
      GoodJob.shutdown
    end

    MAIN_PID = Process.pid
    at_exit do
      GoodJob.shutdown if Process.pid == MAIN_PID
    end
    ```

  GoodJob is compatible with Puma's `preload_app!` method.

  For Passenger:

    ```Ruby
    if defined? PhusionPassenger
      PhusionPassenger.on_event :starting_worker_process do |forked|
        # If `forked` is true, we're in smart spawning mode.
        # https://www.phusionpassenger.com/docs/advanced_guides/in_depth/ruby/spawn_methods.html#smart-spawning-hooks
        if forked
          GoodJob.logger.info { 'Starting Passenger worker process.' }
          GoodJob.restart
        end
      end

      PhusionPassenger.on_event :stopping_worker_process do
        GoodJob.logger.info { 'Stopping Passenger worker process.' }
        GoodJob.shutdown
      end
    end

    # GoodJob also starts in the Passenger preloader process. This one does not
    # trigger the above events, thus we catch it with `Kernel#at_exit`.
    PRELOADER_PID = Process.pid
    at_exit do
      if Process.pid == PRELOADER_PID
        GoodJob.logger.info { 'Passenger AppPreloader shutting down.' }
        GoodJob.shutdown
      end
    end
    ```

  If you are using cron-style jobs, you might also want to look at your Passenger configuration, especially at [`passenger_pool_idle_time`](https://www.phusionpassenger.com/library/config/nginx/reference/#passenger_pool_idle_time) and [`passenger_min_instances`](https://www.phusionpassenger.com/library/config/nginx/reference/#passenger_min_instances) to make sure there's always at least once process running that can execute cron-style scheduled jobs. See also [Passenger's optimization guide](https://www.phusionpassenger.com/library/config/nginx/optimization/#minimizing-process-spawning) for more information.

### Migrate to GoodJob from a different ActiveJob backend

If your application is already using an ActiveJob backend, you will need to install GoodJob to enqueue and perform newly created jobs _and_ finish performing pre-existing jobs on the previous backend.

1. Enqueue newly created jobs on GoodJob either entirely by setting `ActiveJob::Base.queue_adapter = :good_job` or progressively via individual job classes:

    ```ruby
    # jobs/specific_job.rb
    class SpecificJob < ApplicationJob
      self.queue_adapter = :good_job
      # ...
    end
    ```

1. Continue running executors for both backends. For example, on Heroku it's possible to run [two processes](https://help.heroku.com/CTFS2TJK/how-do-i-run-multiple-processes-on-a-dyno) within the same dyno:

   ```procfile
    # Procfile
    # ...
    worker: bundle exec que ./config/environment.rb & bundle exec good_job & wait -n
    ```

1. Once you are confident that no unperformed jobs remain in the previous ActiveJob backend, code and configuration for that backend can be completely removed.

### Monitor and preserve worked jobs

GoodJob is fully instrumented with [`ActiveSupport::Notifications`](https://edgeguides.rubyonrails.org/active_support_instrumentation.html#introduction-to-instrumentation).

By default, GoodJob will delete job records after they are run, regardless of whether they succeed or not (raising a kind of `StandardError`), unless they are interrupted (raising a kind of `Exception`).

To preserve job records for later inspection, set an initializer:

```ruby
# config/initializers/good_job.rb
GoodJob.preserve_job_records = true
```

It is also necessary to delete these preserved jobs from the database after a certain time period:

- For example, in a Rake task:

    ```ruby
    GoodJob.cleanup_preserved_jobs # Will keep 1 day of job records by default.
    GoodJob.cleanup_preserved_jobs(older_than: 7.days) # It also takes custom arguments.
    ```

- For example, using the `good_job` command-line utility:

    ```bash
    bundle exec good_job cleanup_preserved_jobs --before-seconds-ago=86400
    ```

### PgBouncer compatibility

GoodJob is not compatible with PgBouncer in _transaction_ mode, but is compatible with PgBouncer's _connection_ mode. GoodJob uses connection-based advisory locks and LISTEN/NOTIFY, both of which require full database connections.

A workaround to this limitation is to make a direct database connection available to GoodJob. With Rails 6.0's support for [multiple databases](https://guides.rubyonrails.org/active_record_multiple_databases.html), a direct connection to the database can be configured:

1. Define a direct connection to your database that is not proxied through PgBouncer, for example:

    ```yml
    # config/database.yml

    production:
      primary:
        url: postgres://pgbouncer_host/my_database
      primary_direct:
        url: postgres://database_host/my_database
    ```

1. Create a new ActiveRecord base class that uses the direct database connection

    ```ruby
    # app/models/application_direct_record.rb

    class ApplicationDirectRecord < ActiveRecord::Base
      self.abstract_class = true
      connects_to database: :primary_direct
    end
    ```

1. Configure GoodJob to use the newly created ActiveRecord base class:

    ```ruby
    # config/initializers/good_job.rb

    GoodJob.active_record_parent_class = "ApplicationDirectRecord"
    ```

### CLI HTTP health check probes

GoodJob's CLI offers an http health check probe to better manage process lifecycle in containerized environments like Kubernetes:

```bash
# Run the CLI with a health check on port 7001
good_job start --probe-port=7001

# or via an environment variable
GOOD_JOB_PROBE_PORT=7001 good_job start

# Probe the status
curl localhost:7001/status
curl localhost:7001/status/started
curl localhost:7001/status/connected
```

Multiple health checks are available at different paths:

- `/` or `/status`: the CLI process is running
- `/status/started`: the multithreaded job executor is running
- `/status/connected`: the database connection is established

This can be configured, for example with Kubernetes:

```yaml
spec:
  containers:
    - name: good_job
      image: my_app:latest
      env:
        - name: RAILS_ENV
          value: production
        - name: GOOD_JOB_PROBE_PORT
          value: 7001
      command:
          - good_job
          - start
      ports:
        - name: probe-port
          containerPort: 7001
      startupProbe:
        httpGet:
          path: "/status/started"
          port: probe-port
        failureThreshold: 30
        periodSeconds: 10
      livenessProbe:
        httpGet:
          path: "/status/connected"
          port: probe-port
        failureThreshold: 1
        periodSeconds: 10
```

## Contribute

Contributions are welcomed and appreciated 🙏

- Review the [Prioritized Project Backlog](https://github.com/bensheldon/good_job/projects/1).
- Open a new Issue or contribute to an [existing Issue](https://github.com/bensheldon/good_job/issues). Questions or suggestions are fantastic.
- Participate according to our [Code of Conduct](https://github.com/bensheldon/good_job/projects/1).

### Gem development

To run tests:

```bash
# Clone the repository locally
$ git clone git@github.com:bensheldon/good_job.git

# Set up the local environment
$ bin/setup

# Run the tests
$ bin/rspec
```

This gem uses Appraisal to run tests against multiple versions of Rails:

```bash
# Install Appraisal(s) gemfiles
$ bundle exec appraisal

# Run tests
$ bundle exec appraisal bin/rspec
```

For developing locally within another Ruby on Rails project:

```bash
# Within Ruby on Rails directory...
$ bundle config local.good_job /path/to/local/git/repository

# Confirm that the local copy is used
$ bundle install

# => Using good_job 0.1.0 from https://github.com/bensheldon/good_job.git (at /Users/You/Projects/good_job@dc57fb0)
```

### Release

Package maintainers can release this gem by running:

```bash
# Sign into rubygems
$ gem signin

# Add a .env file with the following:
# CHANGELOG_GITHUB_TOKEN= # Github Personal Access Token

# Update version number, changelog, and create git commit:
$ bundle exec rake release[minor] # major,minor,patch

# ..and follow subsequent directions.
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
