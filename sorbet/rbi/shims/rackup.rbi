# Manually exported via Tapioca because rackup is not compatible with Rack 2.0
# which is used for development, but Rackup is is necessary as a fallback for
# Rack 3.0 compatibility. And Rackup 1.0 is bugged.
#
# https://github.com/rack/rackup/issues/13#issuecomment-2186788166

module Rackup; end
module Rackup::Handler
  class << self
    # source://rackup//lib/rackup/handler.rb#30
    def [](name); end

    # source://rackup//lib/rackup/handler.rb#84
    def default; end

    # source://rackup//lib/rackup/handler.rb#40
    def get(name); end

    # Select first available Rack handler given an `Array` of server names.
    # Raises `LoadError` if no handler was found.
    #
    #   > pick ['puma', 'webrick']
    #   => Rackup::Handler::WEBrick
    #
    # @raise [LoadError]
    #
    # source://rackup//lib/rackup/handler.rb#69
    def pick(server_names); end

    # Register a named handler class.
    #
    # source://rackup//lib/rackup/handler.rb#18
    def register(name, klass); end

    # Transforms server-name constants to their canonical form as filenames,
    # then tries to require them but silences the LoadError if not found
    #
    # Naming convention:
    #
    #   Foo # => 'foo'
    #   FooBar # => 'foo_bar.rb'
    #   FooBAR # => 'foobar.rb'
    #   FOObar # => 'foobar.rb'
    #   FOOBAR # => 'foobar.rb'
    #   FooBarBaz # => 'foo_bar_baz.rb'
    #
    # source://rackup//lib/rackup/handler.rb#106
    def require_handler(prefix, const_name); end
  end
end

# source://rackup//lib/rackup/version.rb#7
Rackup::VERSION = T.let(T.unsafe(nil), String)
