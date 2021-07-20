# frozen_string_literal: true
RSpec.configure do |c|
  if RUBY_PLATFORM.include?('java')
    puts "Excluding System Tests in JRuby"
    c.filter_run_excluding type: :system
    c.filter_run_excluding :skip_if_java
  end
end
