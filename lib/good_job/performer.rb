module GoodJob
  #
  # Performer queries the database for jobs and performs them on behalf of a
  # {Scheduler}. It mainly functions as glue between a {Scheduler} and the jobs
  # it should be executing.
  #
  # The Performer enforces a callable that does not rely on scoped/closure
  # variables because they might not be available when executed in a different
  # thread.
  #
  class Performer
    # @!attribute [r] name
    # @return [String]
    #   a meaningful name to identify the performer in logs and for debugging.
    #   This is usually set to the list of queues the performer will query,
    #   e.g. +"-transactional_messages,batch_processing"+.
    attr_reader :name

    # @param target [Object]
    #   An object that can perform jobs. It must respond to +method_name+ by
    #   finding and performing jobs and is usually a {Job} query,
    #   e.g. +GoodJob::Job.where(queue_name: ['queue1', 'queue2'])+.
    # @param method_name [Symbol]
    #   The name of a method on +target+ that finds and performs jobs.
    # @param name [String]
    #   A name for the performer to be used in logs and for debugging.
    # @param filter [#call]
    #   Used to determine whether the performer should be used in GoodJob's
    #   current state. GoodJob state is a +Hash+ that will be passed as the
    #   first argument to +filter+ and includes info like the current queue.
    def initialize(target, method_name, name: nil, filter: nil)
      @target = target
      @method_name = method_name
      @name = name
      @filter = filter
    end

    # Find and perform any eligible jobs.
    def next
      @target.public_send(@method_name)
    end

    # Tests whether this performer should be used in GoodJob's current state by
    # calling the +filter+ callable set in {#initialize}. Always returns +true+
    # if there is no filter.
    #
    # For example, state will be a LISTEN/NOTIFY message that is passed down
    # from the Notifier to the Scheduler. The Scheduler is able to ask
    # its performer "does this message relate to you?", and if not, ignore it
    # to minimize thread wake-ups, database queries, and thundering herds.
    #
    # @return [Boolean] whether the performer's {#next} method should be
    #   called in the current state.
    def next?(state = {})
      return true unless @filter.respond_to?(:call)

      @filter.call(state)
    end
  end
end
