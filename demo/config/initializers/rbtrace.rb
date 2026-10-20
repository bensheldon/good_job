# Attach to a running process with rbtrace, e.g. to take a heap dump:
#   $ bundle exec rbtrace --pid PID --eval 'Thread.new { require "objspace"; GC.start; File.open("tmp/heap-#{Process.pid}.json", "w") { |io| ObjectSpace.dump_all(output: io) } }.join; "done"'
# Then analyze it with the sheap gem.
#
# rbtrace doesn't survive a fork, so a clustered Puma server requires it in each worker
# after forking instead (before_worker_boot in config/puma.rb).
clustered_server = (defined?(Rails::Server) || defined?(Puma::Launcher)) && ENV.fetch("WEB_CONCURRENCY", 0).to_i > 0
if ActiveModel::Type::Boolean.new.cast(ENV.fetch('RBTRACE', nil)) && !clustered_server
  require 'rbtrace'

  # Pause boot so there's time to attach from another terminal
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('RBTRACE_TTY', nil))
    $stdout.puts "Enabled rbtrace. Example commands:"
    $stdout.puts "  Show all method calls: $ bundle exec rbtrace --pid #{Process.pid} --firehose"
    $stdout.puts "  Debug Rails deadlock: $ bundle exec rbtrace --pid #{Process.pid} --eval \"puts output = ActionDispatch::DebugLocks.new(nil).send(:render_details, nil); output\""
    $stdout.puts 'Press Enter to continue...'
    $stdin.gets
  end
end
