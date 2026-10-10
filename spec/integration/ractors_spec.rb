# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Ractors' do
  # GoodJob.ractorize! freezes global state, so it is run in a separate process.
  it 'makes the adapter and global state shareable' do
    skip "Ractors require Ruby 4.0+" if RUBY_VERSION < "4.0"
    skip "Rails does not support Ractors" unless GoodJob::Ractors.enabled? && Rails::Application.method_defined?(:ractorize!)

    script = <<~RUBY
      GoodJob.logger = ActiveSupport::Ractors::Logger.new
      GoodJob::LogSubscriber.loggers.replace([GoodJob.logger])
      GoodJob.ractorize!
      adapter = GoodJob::Adapter.new(execution_mode: :async_all)
      Ractor.make_shareable(adapter)
      adapter.shutdown
      puts [
        Ractor.shareable?(GoodJob.configuration),
        Ractor.shareable?(GoodJob.handled_exceptions),
        Ractor.shareable?(adapter),
        adapter.async_started?,
      ].inspect
    RUBY

    output, status = Open3.capture2e({ "RAILS_ENV" => "test" }, "bin/rails", "runner", script, chdir: Rails.root)

    expect(status).to be_success, output
    expect(output.lines.last.strip).to eq "[true, true, true, false]"
  end
end
