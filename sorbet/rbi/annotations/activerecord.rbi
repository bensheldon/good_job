# typed: strict

# DO NOT EDIT MANUALLY
# This file was pulled from https://raw.githubusercontent.com/Shopify/rbi-central/main.
# Please run `bin/tapioca annotations` to update it.

class ActiveRecord::Schema
  sig {params(info: T::Hash[T.untyped, T.untyped], blk: T.proc.bind(ActiveRecord::Schema).void).void}
  def self.define(info = nil, &blk); end
end

class ActiveRecord::Migration::Current < ActiveRecord::Migration
  include ActiveRecord::ConnectionAdapters::SchemaStatements
end