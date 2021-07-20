# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Daemon, skip_if_java: true do
  let(:pidfile) { Rails.application.root.join('tmp/pidfile.pid') }
  let(:daemon) { described_class.new(pidfile: pidfile) }

  before do
    FileUtils.mkdir_p Rails.application.root.join('tmp')
    allow(Process).to receive(:daemon)
    allow(daemon).to receive(:at_exit)
  end

  after do
    File.delete(pidfile)
  end

  describe '#daemonize' do
    it 'calls Process.daemon' do
      daemon.daemonize
      expect(Process).to have_received :daemon
    end

    it 'writes a pidfile' do
      expect do
        daemon.daemonize
      end.to change { Pathname.new(pidfile).exist? }.from(false).to(true)
    end

    context 'when a pidfile already exists' do
      before do
        File.open(pidfile, "w") { |f| f.write(Process.pid) }
      end

      it 'aborts with a message' do
        expect { daemon.daemonize }.to output("A server is already running. Check #{pidfile}\n").to_stderr.and raise_error SystemExit
      end
    end
  end
end
