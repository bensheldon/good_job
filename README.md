# GoodJob

GoodJob is a multithreaded, Postgres-based ActiveJob backend for Ruby on Rails.

## Usage

1. Create a database migration:
    ```bash
    bin/rails g migration CreateGoodJobs
    ```

    And then add to the newly created file:

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
        end
      end
    end
    ```
1. Configure the ActiveJob adapter:
    ```ruby
    # config/environments/production.rb
    config.active_job.queue_adapter = GoodJob::Adapter.new

    # config/environments/development.rb
    config.active_job.queue_adapter = GoodJob::Adapter.new(inline: true)
    ```

1. In production, the scheduler is designed to run in its own process:

```ruby
# TBD
```

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'good_job', github: 'bensheldon/good_job'
```

And then execute:
```bash
$ bundle
```

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

For developing locally within another Ruby on Rails project:

```bash
# Within Ruby on Rails directory...
$ bundle config local.good_job /path/to/local/git/repository

# Confirm that the local copy is used
$ bundle install

# => Using good_job 0.1.0 from https://github.com/bensheldon/good_job.git (at /Users/You/Projects/good_job@dc57fb0)
```

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
