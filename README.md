# GoodJob

GoodJob is a multithreaded, Postgres-based ActiveJob backend for Ruby on Rails.

Inspired by [Delayed::Job](https://github.com/collectiveidea/delayed_job) and [Que](https://github.com/que-rb/que), GoodJob’s design principles are:

- Stand on the shoulders of ActiveJob. For example, [exception](https://edgeguides.rubyonrails.org/active_job_basics.html#exceptions) and [retry](https://edgeguides.rubyonrails.org/active_job_basics.html#retrying-or-discarding-failed-jobs) behavior. 
- Stand on the shoulders of Ruby on Rails. For example, ActiveRecord ORM, connection pools, and [multithreaded support](https://guides.rubyonrails.org/threading_and_code_execution.html) with [Concurrent-Ruby](https://github.com/ruby-concurrency/concurrent-ruby).
- Stand on the shoulders of Postgres. For example, Advisory Locks.
- Convention over simplicity over performance. 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'good_job'
```

And then execute:
```bash
$ bundle install
```

## Usage

1. Create a database migration:
    ```bash
    $ bin/rails g migration CreateGoodJobs
    ```

    Add to the newly created migration file:

    ```ruby
    class CreateGoodJobs < ActiveRecord::Migration[6.0]
      def change
        enable_extension 'pgcrypto'

        create_table :good_jobs, id: :uuid do |t|
          t.timestamps

          t.text :queue_name
          t.integer :priority
          t.jsonb :serialized_params
          t.timestamp :scheduled_at
   
          t.index :scheduled_at
          t.index [:queue_name, :scheduled_at]
        end
      end
    end
    ```
    
    Run the migration:
    
    ```bash
    $ bin/rails db:migrate
    ```
    
1. Configure the ActiveJob adapter:
    ```ruby
    # config/application.rb
    config.active_job.queue_adapter = :good_job
    ```
    
    By default, using `:good_job` is equivalent to manually configuring the adapter:
    
    ```ruby
    # config/environments/development.rb
    config.active_job.queue_adapter = GoodJob::Adapter.new(inline: true)
   
    # config/environments/test.rb
    config.active_job.queue_adapter = GoodJob::Adapter.new(inline: true)
   
    # config/environments/production.rb
    config.active_job.queue_adapter = GoodJob::Adapter.new
    ```

1. In production, the scheduler is designed to run in its own process:
    ```bash
    $ bundle exec good_job
    ```
   
   Configuration options available with `help`:
   ```bash
   $ bundle exec good_job help start
   
   # Usage:
   #  good_job start
   #
   # Options:
   #   [--max-threads=N]         # Maximum number of threads to use for working jobs (default: ActiveRecord::Base.connection_pool.size)
   #   [--queues=queue1,queue2]  # Queues to work from. Separate multiple queues with commas (default: *)
   #   [--poll-interval=N]       # Interval between polls for available jobs in seconds (default: 1)
   ```
   
### Configuring Job Execution Threads
    
GoodJob executes enqueued jobs using threads. There is a lot than can be said about [multithreaded behavior in Ruby on Rails](https://guides.rubyonrails.org/threading_and_code_execution.html), but briefly:

- Each GoodJob execution thread requires its own database connection, which are automatically checked out from Rails’s connection pool. _Allowing GoodJob to schedule more threads than are available in the database connection pool can lead to timeouts and is not recommended._ 
- The maximum number of GoodJob threads can be configured, in decreasing precedence:
    1. `$ bundle exec good_job --max_threads 4`
    2. `$ GOOD_JOB_MAX_THREADS=4 bundle exec good_job`
    3. `$ RAILS_MAX_THREADS=4 bundle exec good_job`
    4. Implicitly via Rails's database connection pool size (`ActiveRecord::Base.connection_pool.size`)

## Development

To run tests:

```bash
# Clone the repository locally
$ git clone git@github.com:bensheldon/good_job.git

# Set up the local environment
$ bin/setup_test

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

## Releasing

Package maintainers can release this gem with the following [gem-release](https://github.com/svenfuchs/gem-release) command:

```bash
# Sign into rubygems
$ gem signin

# Update version number, changelog, and create git commit:
$ bundle exec rake commit_version[minor] # major,minor,patch

# ..and follow subsequent directions. 
```

## Contributing

Contribution directions go here.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
