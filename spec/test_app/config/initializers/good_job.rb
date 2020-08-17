if ENV['RBTRACE']
  require 'sigdump/setup'
  require 'rbtrace'
  sleep 1
  $stdout.puts "Run $ bundle exec rbtrace --pid #{Process.pid} --firehose"
  $stdout.puts 'Press Enter to continue'
  $stdin.gets
end

if ENV['GOOD_JOB_EXECUTION_MODE'].present?
  ActiveJob::Base.queue_adapter = :good_job
end
