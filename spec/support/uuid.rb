# frozen_string_literal: true

RSpec::Matchers.define :be_a_uuid do
  match do |actual|
    regexp = /\A\h{8}-\h{4}-(\h{4})-\h{4}-\h{12}\z/
    actual.is_a?(String) && actual.match?(regexp)
  end

  description { "a UUID" }
  failure_message { "expected #{description}" }
  failure_message_when_negated { "did not expect #{description}" }
end

RSpec::Matchers.alias_matcher :a_uuid, :be_a_uuid
