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
      scope :display_all, (lambda do |after_scheduled_at: nil, after_id: nil|
        query = order(Arel.sql('COALESCE(scheduled_at, created_at) DESC, id DESC'))
        if after_scheduled_at.present? && after_id.present?
          query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at), id) < (:after_scheduled_at, :after_id)'), after_scheduled_at: after_scheduled_at, after_id: after_id)
        elsif after_scheduled_at.present?
          query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at)) < (:after_scheduled_at)'), after_scheduled_at: after_scheduled_at)
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

        tsvector = "(to_tsvector('english', serialized_params) || to_tsvector('english', id::text) || to_tsvector('english', COALESCE(error, '')::text))"
        where("#{tsvector} @@ to_tsquery(?)", query)
          .order(sanitize_sql_for_order([Arel.sql("ts_rank(#{tsvector}, to_tsquery(?))"), query]) => 'DESC')
      end)
    end
  end
end
