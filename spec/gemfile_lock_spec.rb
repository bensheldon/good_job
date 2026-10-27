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

  # Bundler drops any locked platform that some gem has no installable variant
  # for whenever it re-resolves (e.g. `bundle update --conservative good_job`
  # during release). Gems that only ship native variants also need their
  # generic (ruby platform) variant locked, as with pg and thruster.
  # Bundler.definition is only the root Gemfile in the development environment;
  # the CI matrix runs against gemfiles/*.gemfile with older Bundlers.
  it 'is complete for every locked platform' do
    skip 'Only checked against the root Gemfile' unless Bundler.default_gemfile.to_s == File.expand_path('../Gemfile', __dir__)

    specs = Bundler::SpecSet.new(lockfile.specs)
    dependencies = Bundler.definition.send(:current_dependencies)

    lockfile.platforms.each do |platform|
      incomplete = specs.incomplete_specs_for_platform(dependencies, platform).map(&:name).uniq
      expect(incomplete).to be_empty, "Bundler would drop #{platform} from Gemfile.lock; no installable variant for: #{incomplete.join(', ')}"
    end
  end
end
