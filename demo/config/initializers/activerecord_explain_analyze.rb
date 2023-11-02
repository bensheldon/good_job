# frozen_string_literal: true

ActiveSupport.on_load(:active_record) do
  begin
    require 'activerecord-explain-analyze'
  rescue LoadError
    next # ignore
  end

  module ActiveRecordExplainAnalyze
    module Relation
      def explain_force_index(analyze: false, format: :text)
        ActiveRecord::Base.connection.execute('SET enable_seqscan = OFF')
        explain(analyze: analyze, format: format)
      ensure
        ActiveRecord::Base.connection.execute('SET enable_seqscan = ON')
      end
    end
  end
end
