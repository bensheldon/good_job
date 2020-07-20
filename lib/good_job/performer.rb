module GoodJob
  class Performer
    def initialize(target, method_name)
      @target = target
      @method_name = method_name
    end

    def next
      @target.public_send(@method_name)
    end
  end
end
