# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::SharedExecutor do
  let(:shared_executor) { described_class.new }

  describe '#shutdown' do
    it 'takes a timeout' do
      shared_executor.shutdown(timeout: -1)
      expect(shared_executor).to be_shutdown
    end
  end

  describe '#restart' do
    it 'shuts down and restarts' do
      shared_executor.restart(timeout: -1)
      expect(shared_executor).to be_running
    end

    it 'starts when shutdown' do
      shared_executor.shutdown(timeout: -1)

      expect do
        shared_executor.restart
      end.to change(shared_executor, :running?).from(nil).to(true)
    end
  end
end
