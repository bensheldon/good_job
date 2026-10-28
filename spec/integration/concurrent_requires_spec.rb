# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'concurrent-ruby requires' do
  # tzinfo and Action Cable `require "concurrent"`, which loads every concurrent-ruby class
  # and hides a missing require. This loads GoodJob as if they only required what they use.
  it 'requires every concurrent-ruby class GoodJob references' do
    script = <<~RUBY
      module Kernel
        alias_method :require_without_concurrent_entrypoint, :require

        def require(path)
          path = "concurrent/map" if ["concurrent", "concurrent-ruby"].include?(path)
          require_without_concurrent_entrypoint(path)
        end
      end

      require "rails/all"
      require "good_job"

      referenced = Dir["lib/**/*.rb"].flat_map do |file|
        File.readlines(file).grep_v(/^\\s*#/).join.scan(/\\bConcurrent::(\\w+)/).flatten
      end
      puts referenced.uniq.reject { |name| Concurrent.const_defined?(name, false) }.sort.inspect
    RUBY

    output, status = Open3.capture2e("ruby", "-e", script, chdir: File.expand_path("../..", __dir__))

    expect(status).to be_success, output
    expect(output.lines.last.strip).to eq "[]"
  end
end
