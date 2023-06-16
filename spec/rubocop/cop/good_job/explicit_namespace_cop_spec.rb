# frozen_string_literal: true

require 'rails_helper'
require 'rubocop'
require 'rubocop/rspec/support'

require_relative './explicit_namespace_cop'

RSpec.describe RuboCop::Cop::GoodJob::ExplicitNamespaceCop do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::Config.new }

  it 'registers an offense when accessing DiscreteExecution' do
    expect_offense(<<~RUBY)
      DiscreteExecution.migrated?
      ^^^^^^^^^^^^^^^^^ GoodJob/ExplicitNamespaceCop: Use GoodJob::DiscreteExecution instead of DiscreteExecution. See https://github.com/bensheldon/good_job/pull/962
    RUBY
  end

  it 'does not register an offense when accessing properly namespaced GoodJob::DiscreteExecution' do
    expect_no_offenses(<<~RUBY)
      GoodJob::DiscreteExecution.migrated?
    RUBY
  end

  it 'does not register an offense when declaring DiscreteExecution' do
    expect_no_offenses(<<~RUBY)
      class DiscreteExecution < GoodJob::BaseRecord
      end
    RUBY
  end
end
