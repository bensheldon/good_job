# frozen_string_literal: true

module GoodJob
  ActiveRecordParentClass = if GoodJob.active_record_parent_class
                              Object.const_get(GoodJob.active_record_parent_class)
                            else
                              ActiveRecord::Base
                            end
end
