# frozen_string_literal: true

module GoodJob
  module ExperimentalExecution
    extend ActiveSupport::Concern

    included do
      # Attempt to acquire an advisory lock on the selected records and
      # return only those records for which a lock could be acquired.
      # @!method advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @param function [String, Symbol]  Postgres Advisory Lock function name to use
      # @return [ActiveRecord::Relation]
      #   A relation selecting only the records that were locked.
      scope :experimental_advisory_lock, (lambda do |column: _advisory_lockable_column, function: advisory_lockable_function, select_limit: nil|
        original_query = self
        original_limit = original_query.arel.ast.limit

        all_rows_cte = Arel::Table.new(:all_rows)
        all_rows_query = original_query.select(*[primary_key.to_s, column.to_s].uniq).except(:limit)
                                       .then { |query| select_limit ? query.limit(select_limit) : query }
        all_rows_composed = Arel::Nodes::As.new(all_rows_cte, Arel::Nodes::SqlLiteral.new([materialized_cte, "(", all_rows_query.to_sql, ")"].join(' ')))

        locked_rows_cte = Arel::Table.new(:locked_rows)
        locked_rows_query = all_rows_cte.project(all_rows_cte[:id])
                                        .where(Arel.sql("#{function}(('x' || substr(md5(#{connection.quote(table_name)} || '-' || #{connection.quote_table_name(all_rows_cte.name)}.#{connection.quote_column_name(column)}::text), 1, 16))::bit(64)::bigint)"))
                                        .tap { |query| query.limit = original_limit.value.value if original_limit.present? }
        locked_rows_composed = Arel::Nodes::As.new(locked_rows_cte, Arel::Nodes::SqlLiteral.new([materialized_cte, "(", locked_rows_query.to_sql, ")"].join(' ')))

        subselect_locked_ids = locked_rows_cte.project(locked_rows_cte[:id])
                                              .with(all_rows_composed, locked_rows_composed)

        original_query.unscoped.except(:limit).where(arel_table[primary_key].in(subselect_locked_ids)).merge(original_query.only(:order))
      end)
    end

    class_methods do
      # Experimental function to replace .perform_with_advisory_lock
      def experimental_dequeue_sql(parsed_queues: nil, queue_select_limit: nil)
        binds = []

        if parsed_queues
          if parsed_queues[:include].present?
            binds << ActiveRecord::Relation::QueryAttribute.new('queue_name', "{ #{parsed_queues[:include].map { |queue| connection.quote(queue) }.join(', ')} }", ActiveRecord::Type::String.new)
            queue_conditional_sql = %[AND "queue_name" = ANY($#{binds.size}::text[])]
          elsif parsed_queues[:exclude].present?
            binds << ActiveRecord::Relation::QueryAttribute.new('queue_name', "{ #{parsed_queues[:exclude].map { |queue| connection.quote(queue) }.join(', ')} }", ActiveRecord::Type::String.new)
            queue_conditional_sql = %[AND "queue_name" != ANY($#{binds.size}::text[])]
          end

          if parsed_queues[:ordered_queues] && parsed_queues[:include].present?
            queue_ordered_clauses = parsed_queues[:include].map.with_index do |queue_name, index|
              %[WHEN "queue_name" = #{connection.quote(queue_name)} THEN #{index}]
            end
            queue_ordered_sql = "(CASE #{queue_ordered_clauses.join(' ')} ELSE #{parsed_queues[:include].size} END) ASC, "
          end
        end

        order_sql = if GoodJob.configuration.smaller_number_is_higher_priority
                      %["priority" ASC NULLS LAST, "created_at" ASC]
                    else
                      %["priority" DESC NULLS LAST, "created_at" ASC]
                    end
        queue_select_limit_sql = queue_select_limit ? "LIMIT #{queue_select_limit}" : ''

        # Future: Use `FOR NO KEY UPDATE SKIP LOCKED`
        [pg_or_jdbc_query(<<~SQL.squish), binds]
          WITH rows AS #{materialized_cte} (
            SELECT "id", "active_job_id"
            FROM #{quoted_table_name}
            WHERE "finished_at" IS NULL
              #{queue_conditional_sql}
              AND ("scheduled_at" IS NULL OR "scheduled_at" <= $#{binds << ActiveRecord::Relation::QueryAttribute.new('scheduled_at', Time.current, ActiveRecord::Type::DateTime.new) and binds.size})
            ORDER BY #{queue_ordered_sql} #{order_sql}
            #{queue_select_limit_sql}
          ), locked_rows AS #{materialized_cte} (
            SELECT *
            FROM "rows"
            WHERE pg_try_advisory_lock(('x' || substr(md5(#{connection.quote(table_name)} || '-' || "rows"."active_job_id"::text), 1, 16))::bit(64)::bigint)
            LIMIT 1
          )
          SELECT *
          FROM #{quoted_table_name}
          WHERE "id" IN (SELECT "id" FROM "locked_rows")
        SQL
      end

      def materialized_cte
        supports_cte_materialization_specifiers? ? 'MATERIALIZED' : ''
      end

      # Finds the next eligible Execution, acquire an advisory lock related to it, and
      # executes the job.
      # @return [ExecutionResult, nil]
      #   If a job was executed, returns an array with the {Execution} record, the
      #   return value for the job's +#perform+ method, and the exception the job
      #   raised, if any (if the job raised, then the second array entry will be
      #   +nil+). If there were no jobs to execute, returns +nil+.
      def experimental_perform_with_advisory_lock(parsed_queues: nil, queue_select_limit: nil)
        execution = nil
        result = nil

        begin
          execution = find_by_sql(*experimental_dequeue_sql(parsed_queues: parsed_queues, queue_select_limit: queue_select_limit), preparable: true).first

          if execution
            execution.reload
            if execution.finished_at
              result = ExecutionResult.new(value: nil, unexecutable: true)
            else
              unless unscoped.unfinished.owns_advisory_locked.exists?(id: execution.id)
                someone_owns = unscoped.unfinished.advisory_locked.exists?(id: execution.id)
                $stdout.puts "finished_at before reload: #{execution.finished_at || 'nil'}; after reload #{execution.reload.finished_at}"
                msg = "UNLOCKED (#{Thread.current.name}) and is owned (#{someone_owns}): #{execution.id}"
                Rails.logger.error(msg)
                $stdout.puts msg
              end

              yield(execution) if block_given?
              result = execution.perform
            end
          end
        ensure
          execution&.advisory_unlock
        end
        execution&.run_callbacks(:perform_unlocked)

        result
      end
    end
  end
end
