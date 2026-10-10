# typed: true

# ActiveSupport::Ractors exists only in Rails versions with Ractor support.
module ActiveSupport
  module Ractors
    class << self
      def unshareable_proc_action; end
      def main?; end
      def make_shareable(obj, copy: false); end
      def try_make_shareable(obj, **kwargs); end
      def try_shareable_proc(proc = nil, &block); end
      def on_main(obj = nil, &block); end
      def store_if_absent(key, &block); end
    end
  end
end

class Ractor
  class IsolationError < ArgumentError; end
end
