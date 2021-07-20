# frozen_string_literal: true
module OutputHelper
  def quiet(&block)
    if ENV['LOUD'].present?
      yield
    else
      expect(&block).to output(/.*/).to_stderr_from_any_process.and output(/.*/).to_stdout_from_any_process
    end
  end
end
RSpec.configure { |c| c.include OutputHelper }
