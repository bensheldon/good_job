# frozen_string_literal: true

module GoodJob
  class Configuration
    # Validates a {Configuration} instance so that misconfigurations can be
    # caught in a test (e.g. `expect(GoodJob.configuration).to be_valid`)
    # rather than at runtime.
    class Validator
      include ActiveModel::Model

      # @return [Configuration]
      attr_accessor :configuration

      validate :validate_cron_entries

      def initialize(configuration)
        super()
        @configuration = configuration
      end

      private

      def validate_cron_entries
        cron_entries = begin
          configuration.cron_entries
        rescue StandardError => e
          errors.add(:cron, "is invalid: #{e.message}")
          nil
        end
        return if cron_entries.nil?

        cron_entries.each do |cron_entry|
          next if cron_entry.valid?

          cron_entry.errors.full_messages.each do |message|
            errors.add(:cron, "entry '#{cron_entry.key}' #{message}")
          end
        end
      end
    end
  end
end
