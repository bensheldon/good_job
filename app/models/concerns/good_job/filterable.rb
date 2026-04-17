# frozen_string_literal: true

module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module Filterable
    extend ActiveSupport::Concern

    included do
      # Get records in display order with optional keyset pagination.
      # @!method display_all(ordered_by: ["created_at", "desc"], after_at: nil, after_id: nil)
      # @!scope class
      # @param ordered_by [Array<String>]
      #   Order to display records, from Filter#ordered_by
      # @param after_id [Numeric, String, nil]
      #   Display records after this ID for keyset pagination
      # @return [ActiveRecord::Relation]
      scope :display_all, (lambda do |ordered_by: %w[created_at desc], after_at: nil, after_id: nil|
        order_column, order_direction = ordered_by
        query = self

        if after_id.present?
          op = order_direction == 'asc' ? Arel::Nodes::GreaterThan : Arel::Nodes::LessThan
          uuid_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid

          cursor_subquery = unscoped.select(arel_table[order_column], arel_table[primary_key]).where(primary_key => after_id)

          # Fall back to after_at if the cursor record has been destroyed.
          # UNION ALL returns the exact DB row first; the fallback row is only used when the subquery is empty.
          # The resulting WHERE clause looks like:
          #   WHERE (created_at, id) < (
          #     SELECT _cursor.* FROM (
          #       SELECT created_at, id FROM good_jobs WHERE id = $after_id  -- exact from DB
          #       UNION ALL
          #       SELECT $after_at, $after_id                                -- fallback if destroyed
          #     ) AS _cursor LIMIT 1
          #   )
          fallback = Arel::SelectManager.new.tap do |m|
            m.project(bind_value(order_column, after_at, ActiveRecord::Type::DateTime),
                      bind_value(primary_key, after_id, uuid_type))
          end
          union = cursor_subquery.arel.union(:all, fallback)
          cursor_arel = Arel::SelectManager.new.tap do |m|
            m.from(Arel::Nodes::As.new(Arel::Nodes::Grouping.new([union]), Arel.sql("_cursor")))
            m.project(Arel.sql("_cursor.*"))
            m.take(1)
          end

          query = query.where(op.new(
                                Arel::Nodes::Grouping.new([arel_table[order_column], arel_table[primary_key]]),
                                Arel::Nodes::Grouping.new([cursor_arel])
                              ))
        end

        query.order Arel.sql("#{order_column} #{order_direction}, #{primary_key} #{order_direction}")
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
        where("#{tsvector} @@ #{to_tsquery_function}('english', CAST(? AS text))", query)
          .order(sanitize_sql_for_order([Arel.sql("ts_rank(#{tsvector}, #{to_tsquery_function}('english', CAST(? AS text)))"), query]) => 'DESC')
      end)
    end

    class_methods do
      def database_supports_websearch_to_tsquery?
        return @_database_supports_websearch_to_tsquery if defined?(@_database_supports_websearch_to_tsquery)

        @_database_supports_websearch_to_tsquery = connection_pool.with_connection { |conn| conn.postgresql_version >= 110000 }
      end
    end
  end
end
