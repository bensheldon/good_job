# typed: true

# GoodJob::ActiveRecordParentClass is configurable at runtime, so Sorbet can't
# resolve it statically (app/models/good_job/active_record_parent_class.rb is
# `typed: ignore`). Assume the default.
module GoodJob
  ActiveRecordParentClass = ActiveRecord::Base
end
