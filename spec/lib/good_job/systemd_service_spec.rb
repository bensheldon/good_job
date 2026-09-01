# frozen_string_literal: true

require 'rails_helper'

# Creates a socket at a temp path that you can read from during a test.
class TestSocket
  attr_accessor :path

  def initialize
    @socket = Socket.new(:UNIX, :DGRAM, 0)
    @path = nil
    Dir::Tmpname.create("test_socket") do |filepath|
      @path = filepath
      socket_info = Addrinfo.unix(@path)
      @socket.bind(socket_info)
    end
  end

  def close
    @socket.close
    File.unlink(@path) if @path
  end

  def read(maxlen = 16)
    @socket.recvfrom(maxlen)[0]
  end
end

# These are skipped on JRuby because it appears to have some issues with binding
# to UNIX domain sockets, which all these tests rely on.
RSpec.describe GoodJob::SystemdService, :skip_if_java do
  let(:systemd_socket) { TestSocket.new }

  before do
    stub_const('ENV', ENV.to_hash.merge({ 'NOTIFY_SOCKET' => systemd_socket.path }))
  end

  after do
    systemd_socket.close
  end

  it 'notifies systemd about starting and stopping' do
    systemd = described_class.new
    systemd.start
    expect(systemd_socket.read).to eq('READY=1')

    expect(systemd.notifying?).to be(false)

    systemd.stop
    expect(systemd_socket.read).to eq('STOPPING=1')
  end

  it 'sends stopping notification before running #stop block' do
    systemd = described_class.new

    block_ran = false
    systemd.stop do
      expect(systemd_socket.read).to eq('STOPPING=1')
      block_ran = true
    end

    expect(block_ran).to be(true)
  end

  describe '#stopping' do
    it 'notifies systemd that shutdown has begun while leaving the watchdog running' do
      stub_const('ENV', ENV.to_hash.merge({ 'WATCHDOG_USEC' => '500000' }))

      systemd = described_class.new
      systemd.start
      systemd_socket.read

      systemd.stopping

      expect(systemd_socket.read).to eq('STOPPING=1')
      expect(systemd.notifying?).to be(true)

      systemd.stop
    end

    it 'notifies systemd only once, even when #stop follows' do
      allow(GoodJob::SdNotify).to receive(:stopping).and_call_original

      systemd = described_class.new
      systemd.stopping
      systemd.stop

      expect(GoodJob::SdNotify).to have_received(:stopping).once
      expect(systemd_socket.read).to eq('STOPPING=1')
    end
  end

  it 'sends watchdog notifications when configured' do
    stub_const('ENV', ENV.to_hash.merge({ 'WATCHDOG_USEC' => '500000' }))

    systemd = described_class.new
    systemd.start
    systemd_socket.read
    expect(systemd.notifying?).to be(true)

    wait_until(max: 1) { expect(systemd_socket.read).to eq('WATCHDOG=1') }

    systemd.stop
  end
end
