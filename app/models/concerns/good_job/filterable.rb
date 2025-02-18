# frozen_string_literal: true

module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module Filterable
    extend ActiveSupport::Concern

    included do
      # Get records in display order with optional keyset pagination.
      # @!method display_all(after_scheduled_at: nil, after_id: nil)
      # @!scope class
      # @param after_scheduled_at [DateTime, String, nil]
      #   Display records scheduled after this time for keyset pagination
      # @param after_id [Numeric, String, nil]
      #   Display records after this ID for keyset pagination
      # @return [ActiveRecord::Relation]
      scope :display_all, (lambda do |state: nil, after_scheduled_at: nil, after_id: nil|
        query = if state == 'scheduled'
                  order(Arel.sql('scheduled_at ASC, id DESC'))
                else
                  order(Arel.sql('scheduled_at DESC, id DESC'))
                end
        if after_scheduled_at.present? && after_id.present?
          query = if state == 'scheduled'
                    query.where Arel::Nodes::Grouping.new([arel_table["scheduled_at"], arel_table["id"]]).gteq(Arel::Nodes::Grouping.new([bind_value('scheduled_at', after_scheduled_at, ActiveRecord::Type::DateTime), bind_value('id', after_id, ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid)]))
                  else
                    query.where Arel::Nodes::Grouping.new([arel_table["scheduled_at"], arel_table["id"]]).lt(Arel::Nodes::Grouping.new([bind_value('scheduled_at', after_scheduled_at, ActiveRecord::Type::DateTime), bind_value('id', after_id, ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid)]))
                  end
        elsif after_scheduled_at.present?
          query = query.where arel_table["scheduled_at"].lt(bind_value('scheduled_at', after_scheduled_at, ActiveRecord::Type::DateTime))
        end
        query
      end)

      # Search records by text query.
      # @!method search_text(query)
      # @!scope class
      # @param query [String]
      #   Search Query
      # @return [ActiveRecord::Relation]
      scope :search_text, (lambda do |query|
        query = query.to_s.strip
        next if query.blank?

        # TODO: turn this into proper bind parameters in Arel
        tsvector = "(to_tsvector('english', id::text) || to_tsvector('english', COALESCE(active_job_id::text, '')) || to_tsvector('english', serialized_params) || to_tsvector('english', COALESCE(serialized_params->>'arguments', '')) || to_tsvector('english', COALESCE(error, '')) || to_tsvector('english', COALESCE(array_to_string(labels, ' '), '')))"
        to_tsquery_function = database_supports_websearch_to_tsquery? ? 'websearch_to_tsquery' : 'plainto_tsquery'
        where("#{tsvector} @@ #{to_tsquery_function}(?)", query)
          .order(sanitize_sql_for_order([Arel.sql("ts_rank(#{tsvector}, #{to_tsquery_function}(?))"), query]) => 'DESC')
      end)
    end

    class_methods do
      def database_supports_websearch_to_tsquery?
        return @_database_supports_websearch_to_tsquery if defined?(@_database_supports_websearch_to_tsquery)

        @_database_supports_websearch_to_tsquery = connection.postgresql_version >= 110000
      end
    end
  end
end
