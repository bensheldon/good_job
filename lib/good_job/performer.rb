module GoodJob
  class Performer
    attr_reader :name

    def initialize(target, method_name, name: nil, filter: nil)
      @target = target
      @method_name = method_name
      @name = name
      @filter = filter
    end

    def next
      @target.public_send(@method_name)
    end

    def next?(state = {})
      return true unless @filter.respond_to?(:call)

      @filter.call(state)
    end
  end
end
