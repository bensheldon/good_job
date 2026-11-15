# typed: true
# frozen_string_literal: true

module GoodJob
  class BaseChart
    def start_end_binds
      end_time = Time.current
      start_time = end_time - 1.day

      [
        ActiveRecord::Relation::QueryAttribute.new('start_time', start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', end_time, ActiveRecord::Type::DateTime.new),
      ]
    end
  end
end
