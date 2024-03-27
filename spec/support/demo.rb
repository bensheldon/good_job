# frozen_string_literal: true

RSpec.configure do |c|
  c.filter_run_excluding(:demo_only) if ENV["CI"] && !ENV["TEST_DEMO"]
end
