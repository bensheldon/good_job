# frozen_string_literal: true

module GoodJob
  #
  # Adds Postgres row-locking (FOR UPDATE SKIP LOCKED) capabilities to an ActiveRecord record.
  #
  module RowLockable
    extend ActiveSupport::Concern

    included do
      scope :row_lock, (lambda do |locked_by_id:, locked_at: Time.current|
        original_query = self

        jobs_table = arel_table
        bind_locked_by_id = ActiveRecord::Relation::QueryAttribute.new("lock_id", locked_by_id, ActiveRecord::Type::String.new)
        bind_locked_at = ActiveRecord::Relation::QueryAttribute.new("current_time", locked_at, ActiveRecord::Type::DateTime.new)

        subquery = original_query.select(:id).arel
        subquery.lock(Arel.sql("FOR NO KEY UPDATE SKIP LOCKED"))

        # Get the binds from the original_query using to_sql_and_binds
        _sql, original_query_binds, _preparable = connection.send(:to_sql_and_binds, original_query.arel)

        # Build the update manager
        update_manager = Arel::UpdateManager.new
        update_manager.table(jobs_table)
        update_manager.set([
                             [jobs_table[:locked_at], Arel::Nodes::BindParam.new(bind_locked_at)],
                             [jobs_table[:locked_by_id], Arel::Nodes::BindParam.new(bind_locked_by_id)],
                           ])
        update_manager.where(jobs_table[:id].in(subquery))
        update_manager.take(1)

        update_node = Arel::Nodes::UpdateStatement.new
        update_node.relation = update_manager.ast.relation
        update_node.values = update_manager.ast.values
        update_node.wheres = update_manager.ast.wheres

        results = connection.exec_query(
          Arel.sql("#{update_node.to_sql} RETURNING *"),
          "Lock Next Job",
          [bind_locked_at, bind_locked_by_id] + original_query_binds
        )

        results.map { |result| instantiate(result.stringify_keys) }
      end)

      scope :row_locked, -> { where.not(locked_by_id: nil) }
      scope :row_unlocked, -> { where(locked_by_id: nil) }
    end

    def row_locked?
      locked_by_id.present?
    end

    def row_unlock
      update!(locked_by_id: nil, locked_at: nil)
    end
  end
end
