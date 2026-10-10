# typed: true

# Minimal shim: `tapioca gem farce` fails because Farce's global require hook breaks Skylight under Bundler.require.
module Farce
  def self.clock(at: nil, in: nil); end

  class ClosedQueueError < StandardError; end
  class Atom; end
  class Counter; end
  class Flag; end
  class Lock; end
  class Signal; end

  module Unshared
    class Atom; end
    class Lazy; end
    class Map; end
    class Queue; end
    class Set; end
    class TimerQueue; end
    class Vector; end
  end
end
