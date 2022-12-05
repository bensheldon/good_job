# typed: strict

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

class ActionController::API
  MODULES = T.let(T.unsafe(nil), T::Array[T.untyped])
end

module ActionController::Flash::ClassMethods
  sig { params(types: Symbol).void }
  def add_flash_types(*types); end
end

module ActionController::Helpers::ClassMethods
  sig { returns(ActionView::Base) }
  def helpers; end
end

class ActionController::Metal < AbstractController::Base
  sig { returns(ActionController::Parameters) }
  def params; end

  sig { returns(ActionDispatch::Request) }
  def request; end

  sig { returns(ActionDispatch::Response) }
  def response; end
end

module ActionController::MimeResponds
  sig { params(mimes: T.nilable(Symbol), block: T.nilable(T.proc.params(arg0: ActionController::MimeResponds::Collector).void)).void }
  def respond_to(*mimes, &block); end
end

class ActionController::Parameters
  sig { params(other: T.any(String, ActionController::Parameters)).returns(T::Boolean) }
  def ==(other); end

  sig { params(key: T.any(String, Symbol), value: T.untyped).void }
  def []=(key, value); end

  sig { returns(T.nilable(T::Array[T.any(String, Symbol)])) }
  def always_permitted_parameters; end

  sig { params(obj: T.nilable(T::Array[T.any(String, Symbol)])).void }
  def always_permitted_parameters=(obj); end

  sig { returns(T.untyped) }
  def deep_dup; end

  sig { params(key: T.any(String, Symbol), block: T.untyped).returns(T.untyped) }
  def delete(key, &block); end

  sig { params(keys: T.any(String, Symbol)).returns(T.untyped) }
  def dig(*keys); end

  sig { params(block: T.untyped).returns(T.untyped) }
  def each_pair(&block); end

  # each is an alias of each_pair
  sig { params(block: T.untyped).returns(T.untyped) }
  def each(&block); end

  sig { params(keys: T.any(String, Symbol)).returns(ActionController::Parameters) }
  def except(*keys); end

  sig { params(keys: T.any(String, Symbol)).returns(T.untyped) }
  def extract!(*keys); end

  sig { params(key: T.any(String, Symbol), args: T.untyped).returns(T.untyped) }
  def fetch(key, *args); end

  sig { returns(String) }
  def inspect; end

  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def merge!(other_hash); end

  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def merge(other_hash); end

  sig { returns(T.untyped) }
  def parameters; end

  sig { returns(T.self_type) }
  def permit!; end

  # You can pass _a lot_ of stuff to permit, so filters is left untyped for now.
  sig { params(filters: T.untyped).returns(ActionController::Parameters) }
  def permit(*filters); end

  sig { params(new_permitted: T.untyped).void }
  def permitted=(new_permitted); end

  sig { returns(T::Boolean) }
  def permitted?; end

  sig { params(block: T.untyped).returns(T.untyped) }
  def reject!(&block); end

  # delete_if is an alias of reject!
  sig { params(block: T.untyped).returns(T.untyped) }
  def delete_if(&block); end

  sig { params(block: T.untyped).returns(T.untyped) }
  def reject(&block); end

  sig { params(key: T.any(String, Symbol)).returns(T.nilable(T.any(String, Numeric, ActionController::Parameters))) }
  def [](key); end

  sig { params(key: T.any(String, Symbol, T::Array[T.any(String, Symbol)])).returns(T.any(String, Numeric, T::Array[T.untyped], ActionController::Parameters)) }
  def require(key); end

  # required is an alias of require
  sig { params(key: T.any(String, Symbol, T::Array[T.any(String, Symbol)])).returns(T.any(String, Numeric, T::Array[T.untyped], ActionController::Parameters)) }
  def required(key); end

  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def reverse_merge!(other_hash); end

  # with_defaults! is an alias of reverse_merge!
  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def with_defaults!(other_hash); end

  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def reverse_merge(other_hash); end

  # with_defaults is an alias of reverse_merge
  sig { params(other_hash: T.untyped).returns(ActionController::Parameters) }
  def with_defaults(other_hash); end

  sig { params(block: T.untyped).returns(T.nilable(ActionController::Parameters)) }
  def select!(&block); end

  # keep_if is an alias of select!
  sig { params(block: T.untyped).returns(T.nilable(ActionController::Parameters)) }
  def keep_if(&block); end

  sig { params(block: T.untyped).returns(ActionController::Parameters) }
  def select(&block); end

  sig { returns(T.any(Symbol, T::Boolean)) }
  def self.action_on_unpermitted_parameters; end

  sig { params(obj: T.any(Symbol, T::Boolean)).void }
  def self.action_on_unpermitted_parameters=(obj); end

  sig { returns(T::Array[T.any(String, Symbol)]) }
  def self.always_permitted_parameters; end

  sig { params(obj: T::Array[T.any(String, Symbol)]).void }
  def self.always_permitted_parameters=(obj); end

  sig { returns(T::Boolean) }
  def self.permit_all_parameters; end

  sig { params(obj: T::Boolean).void }
  def self.permit_all_parameters=(obj); end

  sig { params(keys: T.any(String, Symbol)).returns(ActionController::Parameters) }
  def slice!(*keys); end

  sig { params(keys: T.any(String, Symbol)).returns(ActionController::Parameters) }
  def slice(*keys); end

  sig { returns(ActiveSupport::HashWithIndifferentAccess) }
  def to_h; end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash; end

  # to_param is an alias of to_query
  sig { params(args: String).returns(T.nilable(String)) }
  def to_param(*args); end

  sig { params(args: String).returns(T.nilable(String)) }
  def to_query(*args); end

  sig { returns(ActiveSupport::HashWithIndifferentAccess) }
  def to_unsafe_h; end

  # to_unsafe_hash is an alias of to_unsafe_h
  sig { returns(ActiveSupport::HashWithIndifferentAccess) }
  def to_unsafe_hash; end

  sig { params(block: T.untyped).returns(ActionController::Parameters) }
  def transform_keys!(&block); end

  sig { params(block: T.untyped).returns(ActionController::Parameters) }
  def transform_keys(&block); end

  sig { returns(ActionController::Parameters) }
  def transform_values!; end

  sig { returns(ActionController::Parameters) }
  def transform_values; end

  sig { params(keys: T.any(String, Symbol)).returns(T.untyped) }
  def values_at(*keys); end
end

module ActionController::RequestForgeryProtection
  sig { returns(T::Boolean) }
  def protect_against_forgery?; end

  sig { params(form_options: T::Hash[T.untyped, T.untyped]).returns(String) }
  def form_authenticity_token(form_options: {}); end
end

module ActionController::RequestForgeryProtection::ClassMethods
  sig { params(options: T::Hash[T.untyped, T.untyped]).void }
  def skip_forgery_protection(options = T.unsafe(nil)); end
end

module ActionController::StrongParameters
  sig { returns(ActionController::Parameters) }
  def params; end
end

module ActionDispatch::Http::Parameters
  sig { returns(ActionController::Parameters) }
  def parameters; end

  # params is an alias of parameters
  sig { returns(ActionController::Parameters) }
  def params; end
end

module ActionDispatch::Integration::Runner
  # @method_missing: delegated to ActionDispatch::Integration::Session
  sig { params(host: String).returns(String) }
  def host!(host); end

  # @method_missing: delegated to ActionDispatch::Integration::Session
  sig { params(flag: T::Boolean).returns(T::Boolean) }
  def https!(flag = true); end
end

class ActionDispatch::IntegrationTest
  # @method_missing: delegated to ActionDispatch::Integration::Runner
  sig { returns(ActionDispatch::Flash::FlashHash) }
  def flash; end

  # @method_missing: delegated to ActionDispatch::Integration::Runner
  sig { returns(ActionDispatch::Request::Session) }
  def session; end

  # @method_missing: delegated to ActionDispatch::Integration::Session
  sig { returns(ActionDispatch::TestResponse) }
  attr_reader :response
end

class ActionDispatch::Request
  # Provides access to the request's HTTP headers, for example:
  #
  # ```ruby
  # request.headers["Content-Type"] # => "text/plain"
  # ```
  sig { returns(ActionDispatch::Http::Headers) }
  def headers; end

  # Returns a `String` with the last requested path including their params.
  #
  # ```ruby
  # # get '/foo'
  # request.original_fullpath # => '/foo'
  #
  # # get '/foo?bar'
  # request.original_fullpath # => '/foo?bar'
  # ```
  sig { returns(String) }
  def original_fullpath; end

  # Returns the `String` full path including params of the last URL requested.
  #
  # ```ruby
  # # get "/articles"
  # request.fullpath # => "/articles"
  #
  # # get "/articles?page=2"
  # request.fullpath # => "/articles?page=2"
  # ```
  sig { returns(String) }
  def fullpath; end

  # Returns the original request URL as a `String`.
  #
  # ```ruby
  # # get "/articles?page=2"
  # request.original_url # => "http://www.example.com/articles?page=2"
  # ```
  sig { returns(String) }
  def original_url; end

  # The `String` MIME type of the request.
  #
  # ```
  # # get "/articles"
  # request.media_type # => "application/x-www-form-urlencoded"
  # ```
  sig { returns(String) }
  def media_type; end

  # Returns the content length of the request as an integer.
  sig { returns(Integer) }
  def content_length; end

  # Returns the IP address of client as a `String`.
  sig { returns(String) }
  def ip; end

  # Returns the IP address of client as a `String`,
  # usually set by the RemoteIp middleware.
  sig { returns(String) }
  def remote_ip; end

  # Returns the unique request id, which is based on either the X-Request-Id header that can
  # be generated by a firewall, load balancer, or web server or by the RequestId middleware
  # (which sets the action_dispatch.request_id environment variable).
  #
  # This unique ID is useful for tracing a request from end-to-end as part of logging or debugging.
  # This relies on the Rack variable set by the ActionDispatch::RequestId middleware.
  sig { returns(String) }
  def request_id; end

  # Returns true if the request has a header matching the given key parameter.
  #
  # ```ruby
  # request.key? :ip_spoofing_check # => true
  # ```
  sig { params(key: Symbol).returns(T::Boolean) }
  def key?(key); end

  # True if the request came from localhost, 127.0.0.1, or ::1.
  sig { returns(T::Boolean) }
  def local?; end
end

module ActionDispatch::Routing::Mapper::Resources
  sig { params(name: T.untyped).returns(T.untyped) }
  def action_path(name); end

  sig { params(block: T.untyped).returns(T.untyped) }
  def collection(&block); end

  sig { params(block: T.untyped).returns(T.untyped) }
  def member(&block); end

  sig { returns(T.untyped) }
  def shallow; end

  sig { returns(T::Boolean) }
  def shallow?; end
end

class ActionDispatch::Routing::RouteSet
  sig { params(block: T.proc.bind(ActionDispatch::Routing::Mapper).void).void }
  def draw(&block); end
end
