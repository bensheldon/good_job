# frozen_string_literal: true

require 'spec_helper'
require 'bundler'

# The root Gemfile.lock must resolve JRuby-specific platforms and gems so that
# the gem can be released (see the release task in the Rakefile). Regenerating
# the lockfile with MRI silently drops them.
RSpec.describe 'Gemfile.lock' do # rubocop:disable RSpec/DescribeClass
  let(:lockfile) do
    Bundler::LockfileParser.new(File.read(File.expand_path('../Gemfile.lock', __dir__)))
  end

  it 'includes the java platform' do
    expect(lockfile.platforms).to include(satisfy { |platform| platform.os == 'java' })
  end

  it 'includes JRuby-specific gems' do
    expect(lockfile.specs.map(&:name)).to include('jdbc-postgres', 'activerecord-jdbcpostgresql-adapter')
  end
end
