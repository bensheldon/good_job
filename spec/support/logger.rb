# frozen_string_literal: true

RSpec.configure do |config|
  config.around do |example|
    Rails.logger.debug { "\n\n---- START EXAMPLE: #{example.full_description} (#{example.location})" }
    example.run
    Rails.logger.debug { "---- END EXAMPLE: #{example.full_description} (#{example.location})\n\n" }
  end
end
