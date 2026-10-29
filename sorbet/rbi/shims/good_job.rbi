# typed: true

# Signatures for GoodJob's own code that Sorbet can't infer statically.
# Kept out of lib/ so that sorbet-runtime is not a dependency.

module GoodJob
  class << self
    sig { returns(T.nilable(String)) }
    def active_record_parent_class; end

    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    def active_record_parent_class=(value); end

    sig { returns(T.untyped) }
    def logger; end

    sig { params(value: T.untyped).returns(T.untyped) }
    def logger=(value); end

    # Boolean, :on_unhandled_error, or any callable
    sig { returns(T.untyped) }
    def preserve_job_records; end

    sig { params(value: T.untyped).returns(T.untyped) }
    def preserve_job_records=(value); end

    sig { returns(T.nilable(T::Boolean)) }
    def retry_on_unhandled_error; end

    sig { params(value: T.nilable(T::Boolean)).returns(T.nilable(T::Boolean)) }
    def retry_on_unhandled_error=(value); end

    sig { returns(T::Array[T.any(T::Class[Exception], String)]) }
    def handled_exceptions; end

    sig { params(value: T::Array[T.any(T::Class[Exception], String)]).returns(T::Array[T.any(T::Class[Exception], String)]) }
    def handled_exceptions=(value); end

    sig { returns(T.untyped) }
    def on_thread_error; end

    sig { params(value: T.untyped).returns(T.untyped) }
    def on_thread_error=(value); end

    sig { returns(GoodJob::Configuration) }
    def configuration; end

    sig { params(value: GoodJob::Configuration).returns(GoodJob::Configuration) }
    def configuration=(value); end

    sig { returns(GoodJob::Capsule) }
    def capsule; end

    sig { params(value: GoodJob::Capsule).returns(GoodJob::Capsule) }
    def capsule=(value); end

    sig { returns(T.nilable(Proc)) }
    def _active_record_configuration; end

    sig { params(value: T.nilable(Proc)).returns(T.nilable(Proc)) }
    def _active_record_configuration=(value); end
  end
end

module GoodJob
  # InstanceRegistry defines `instances` in an `included` block
  class Capsule
    sig { returns(T::Array[GoodJob::Capsule]) }
    def self.instances; end
  end

  class Scheduler
    sig { returns(T::Array[GoodJob::Scheduler]) }
    def self.instances; end
  end

  class Notifier
    sig { returns(T::Array[GoodJob::Notifier]) }
    def self.instances; end
  end

  class Engine
    # Rails::Engine delegates these to the instance
    sig { returns(Pathname) }
    def self.root; end

    sig { params(value: T.untyped).void }
    def self.logger=(value); end
  end

  # mattr_accessor in GoodJob::Dependencies (a concern)
  sig { returns(T::Boolean) }
  def self._framework_ready; end

  sig { params(value: T::Boolean).returns(T::Boolean) }
  def self._framework_ready=(value); end

  class Job
    # Defined via define_singleton_method in LockTypeAccessor.included
    sig { returns(T::Hash[String, Integer]) }
    def self.lock_types; end

    module LockTypeAccessor
      requires_ancestor { ActiveRecord::Base }
    end
  end
end

class Rack::Builder
  sig { params(default_app: T.untyped, options: T.untyped, block: T.nilable(T.proc.bind(Rack::Builder).void)).void }
  def initialize(default_app = nil, **options, &block); end
end

module GoodJob
  module ApplicationHelper
    requires_ancestor { ActionView::Base }
  end

  module IconsHelper
    requires_ancestor { ActionView::Base }
  end

  # Included into GoodJob::Job and GoodJob::Execution
  module FilteredArguments
    sig { returns(T.untyped) }
    def serialized_params; end

    sig { returns(T.nilable(String)) }
    def job_class; end
  end
end

module GoodJob
  class Job
    # Defined in GoodJob::Job::Lockable::ClassMethods (an ActiveSupport::Concern)
    class PrivateRelation
      sig { params(select_limit: T.nilable(Integer), block: T.untyped).returns(T.untyped) }
      def with_advisory_lock_claim(select_limit: nil, &block); end

      sig { params(locked_by_id: T.untyped, locked_at: T.untyped, lock_type: T.untyped, block: T.untyped).returns(T.untyped) }
      def with_skip_locked_claim(locked_by_id:, locked_at:, lock_type:, &block); end

      sig { params(locked_by_id: T.untyped, locked_at: T.untyped, lock_type: T.untyped, block: T.untyped).returns(T.untyped) }
      def with_hybrid_lock_claim(locked_by_id:, locked_at:, lock_type:, &block); end
    end
  end

  class ApplicationController
    sig { returns(T.all(ActionView::Base, GoodJob::ApplicationHelper)) }
    def self.helpers; end
  end

  module IconsHelper
    # GoodJob::Engine route helper
    sig { params(args: T.untyped).returns(String) }
    def frontend_static_path(*args); end
  end

  module LatencyMetric
    class Base
      # Implemented by subclasses
      sig { returns(T.any(String, Symbol)) }
      def key; end
    end
  end
end

class ActiveSupport::TimeWithZone
  # Delegated to Time via method_missing
  sig { params(ndigits: Integer).returns(ActiveSupport::TimeWithZone) }
  def ceil(ndigits = 0); end
end

# Rails < 7.1 compatibility
class ActiveSupport::Logger
  sig { params(logger: T.untyped).returns(Module) }
  def self.broadcast(logger); end
end

# Defined by the host application; referenced by GoodJob controller DSL RBIs,
# which are only generated for GoodJob constants.
module GeneratedMountedHelpers; end

module GoodJob
  class CronEntry
    # A job class, or a job instance or nil when a configured proc enqueues the job itself
    sig { returns(T.nilable(T.any(T.class_of(ActiveJob::Base), ActiveJob::Base))) }
    def resolve_job_class; end
  end
end
