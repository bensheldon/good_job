# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::InstanceRegistry do
  let(:klass) do
    Class.new do
      include GoodJob::InstanceRegistry

      attr_accessor :shutdown
      alias_method :shutdown?, :shutdown

      def initialize
        @shutdown = false
        register_instance
      end

      def start
        @shutdown = false
        register_instance
      end
    end
  end

  it 'registers instances once' do
    instance = klass.new
    instance.start
    expect(klass.instances).to eq [instance]
  end

  describe '.prune' do
    it 'removes and returns only prunable instances' do
      running = klass.new
      stopped = klass.new
      stopped.shutdown = true

      expect(klass.prune).to eq [stopped]
      expect(klass.instances).to eq [running]
    end

    it 'prunes only the given instances' do
      running = klass.new
      stopped = klass.new
      other_stopped = klass.new
      [stopped, other_stopped].each { |instance| instance.shutdown = true }

      expect(klass.prune(running, stopped)).to eq [stopped]
      expect(klass.instances).to eq [running, other_stopped]
    end

    it 'allows pruned instances to re-register' do
      instance = klass.new
      instance.shutdown = true
      klass.prune

      instance.start
      expect(klass.instances).to eq [instance]
    end
  end
end
