# frozen_string_literal: true

ActiveSupport.on_load(:active_record) do
  begin
    require 'activerecord-explain-analyze'
  rescue LoadError
    next # ignore
  end

  module ActiveRecordExplainAnalyze
    module Relation
      alias original_explain explain

      def explain(analyze: false, format: :text, indexscan: false)
        if indexscan
          ActiveRecord::Base.connection.execute('SET enable_seqscan = OFF')
          result = original_explain(analyze: analyze, format: format)
          ActiveRecord::Base.connection.execute('SET enable_seqscan = ON')
          result
        else
          original_explain(analyze: analyze, format: format)
        end
      end
    end
  end
end
