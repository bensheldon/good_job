# frozen_string_literal: true

# Disallow Base.connection to catch deprecated usage early.
# This ensures GoodJob uses lease_connection and with_connection throughout.
if ActiveRecord.respond_to?(:permanent_connection_checkout=)
  ActiveRecord.permanent_connection_checkout = :disallowed
end
