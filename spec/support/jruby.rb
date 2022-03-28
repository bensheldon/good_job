# frozen_string_literal: true
RSpec.configure do |c|
  if RUBY_PLATFORM.include?('java')
    puts "Excluding System Tests in JRuby"
    c.filter_run_excluding type: :system
    c.filter_run_excluding :skip_if_java
  end
end

# https://stackoverflow.com/a/63442278
RSPEC_MUTEX = Mutex.new
RSpec::Core::Example.prepend(Module.new do
  def run_before_example
    RSPEC_MUTEX.synchronize { super }
  end
end)

# It's not possible to wrap the example block itself, but `current_scope` is changed enough to ensure synchronization
RSpec.singleton_class.prepend(Module.new do
  def current_scope=(scope)
    RSPEC_MUTEX.synchronize { super }
  end
end)
