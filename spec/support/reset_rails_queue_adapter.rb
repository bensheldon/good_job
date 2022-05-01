# frozen_string_literal: true
RSpec.configure do |config|
  config.prepend_before do
    # https://github.com/rails/rails/issues/37270
    descendants = ActiveJob::Base.descendants + [ActiveJob::Base]
    descendants.each(&:disable_test_adapter)
  end

  config.around do |example|
    original_adapter = ActiveJob::Base.queue_adapter

    example.run

    ActiveJob::Base.queue_adapter = original_adapter
  end
end
