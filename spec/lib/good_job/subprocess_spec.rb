# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Subprocess do
  let(:configuration) { GoodJob::Configuration.new({}) }

  describe '#report_readiness' do
    let(:readiness_pipe) { IO.pipe }
    let(:readiness_reader) { readiness_pipe.first }
    let(:readiness_writer) { readiness_pipe.last }
    let(:subprocess) { described_class.new(configuration: configuration, readiness_writer: readiness_writer) }

    before { allow(subprocess).to receive(:ready?).and_return(true) }

    after do
      readiness_reader.close unless readiness_reader.closed?
      readiness_writer.close unless readiness_writer.closed?
    end

    it 'heartbeats to the supervisor while it is ready' do
      subprocess.send(:report_readiness)

      expect(readiness_reader.read_nonblock(256)).to eq(described_class::READY_HEARTBEAT)
    end

    it 'does not heartbeat while it is not ready' do
      allow(subprocess).to receive(:ready?).and_return(false)

      subprocess.send(:report_readiness)

      expect { readiness_reader.read_nonblock(256) }.to raise_error(IO::WaitReadable)
    end

    it 'stops heartbeating once the supervisor has closed its end of the pipe' do
      readiness_reader.close

      expect { subprocess.send(:report_readiness) }.not_to raise_error
      expect(subprocess.instance_variable_get(:@readiness_writer)).to be_nil
    end
  end
end
