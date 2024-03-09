if ENV['RBTRACE']
  require 'rbtrace'

  $stdout.puts "Enabled rbtrace. Example commands:"
  $stdout.puts "  Show all method calls: $ bundle exec rbtrace --pid #{Process.pid} --firehose"
  $stdout.puts "  Debug Rails deadlock: $ bundle exec rbtrace --pid #{Process.pid} --eval \"puts output = ActionDispatch::DebugLocks.new(nil).send(:render_details, nil); output\""
  $stdout.puts "  Heap Dump: $ bundle exec rbtrace --pid #{Process.pid} --eval 'Thread.new{require \"objspace\"; GC.start; io=File.open(\"tmp/ruby-heap.\#{Time.now.to_i}.dump\", \"w\"); ObjectSpace.dump_all(output: io); io.close }'"
  $stdout.puts 'Press Enter to continue...'
  $stdin.gets
end
