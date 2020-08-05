module GoodJob
  class Performer
    attr_reader :name

    def initialize(target, method_name, name: nil)
      @target = target
      @method_name = method_name
      @name = name
    end

    def next
      @target.public_send(@method_name)
    end
  end
end
