# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::LifecycleHooks do
  describe 'built-in default hooks' do
    it 'registers a connection-clearing hook for each fork event' do
      expect(GoodJob._lifecycle_hooks[:before_supervisor_fork]).not_to be_empty
      expect(GoodJob._lifecycle_hooks[:before_subprocess_boot]).not_to be_empty
    end
  end

  context 'with an isolated registry' do
    around do |example|
      original = GoodJob._lifecycle_hooks
      GoodJob.clear_lifecycle_hooks
      example.run
    ensure
      GoodJob._lifecycle_hooks = original
    end

    describe '.before_supervisor_fork / .before_subprocess_boot' do
      it 'runs registered blocks in registration order' do
        order = []
        GoodJob.before_supervisor_fork { order << :first }
        GoodJob.before_supervisor_fork { order << :second }

        GoodJob.run_lifecycle_hooks(:before_supervisor_fork)

        expect(order).to eq(%i[first second])
      end

      it 'keeps events isolated from one another' do
        ran = []
        GoodJob.before_supervisor_fork { ran << :supervisor }
        GoodJob.before_subprocess_boot { ran << :subprocess }

        GoodJob.run_lifecycle_hooks(:before_subprocess_boot)

        expect(ran).to eq(%i[subprocess])
      end
    end

    describe '.run_lifecycle_hooks' do
      it 'reports an error from one hook without preventing the others' do
        ran = []
        allow(GoodJob).to receive(:_on_thread_error)
        GoodJob.before_supervisor_fork { raise "boom" }
        GoodJob.before_supervisor_fork { ran << :after_error }

        GoodJob.run_lifecycle_hooks(:before_supervisor_fork)

        expect(ran).to eq(%i[after_error])
        expect(GoodJob).to have_received(:_on_thread_error).with(an_instance_of(RuntimeError))
      end
    end

    describe '.register_lifecycle_hook' do
      it 'raises for an unknown event' do
        expect { GoodJob.register_lifecycle_hook(:nonexistent) { nil } }
          .to raise_error(ArgumentError, /Unknown GoodJob lifecycle event/)
      end
    end

    describe '.clear_lifecycle_hooks' do
      it 'removes every registered hook' do
        GoodJob.before_supervisor_fork { nil }
        GoodJob.before_subprocess_boot { nil }

        GoodJob.clear_lifecycle_hooks

        expect(GoodJob._lifecycle_hooks.values).to all(be_empty)
      end
    end
  end
end
