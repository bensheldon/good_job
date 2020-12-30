if ENV['RBTRACE']
  require 'sigdump/setup'
  require 'rbtrace'
  sleep 1
  $stdout.puts "Enabled rbtrace. Example commands:"
  $stdout.puts "  Show all method calls: $ bundle exec rbtrace --pid #{Process.pid} --firehose"
  $stdout.puts "  Debug Rails deadlock: $ bundle exec rbtrace --pid #{Process.pid} --eval \"puts output = ActionDispatch::DebugLocks.new(nil).send(:render_details, nil); output\""
  $stdout.puts 'Press Enter to continue...'
  $stdin.gets
end
