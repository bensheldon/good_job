# Output Postgres notifications through Rails.logger instead of stderr
if Rails.env.development?
  ActiveSupport.on_load :active_record do
    ActiveRecord::ConnectionAdapters::AbstractAdapter.set_callback :checkout, :before, lambda { |conn|
      raw_connection = conn.raw_connection
      next unless raw_connection.respond_to? :set_notice_receiver

      raw_connection.set_notice_receiver do |result|
        Rails.logger.info("Postgres notice: #{result.error_message}\n#{caller.join("\n")}")
      end
    }
  end
end
