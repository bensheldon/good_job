# frozen_string_literal: true

RSpec.configure do |config|
  config.after do
    Timecop.return
  end
end
