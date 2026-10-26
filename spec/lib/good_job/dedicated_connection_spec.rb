# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::DedicatedConnection do
  let(:connection) { described_class.new }

  after do
    connection.shutdown
  end

  describe '#connected?' do
    it 'becomes true when connected and false when shut down' do
      connection.start
      expect(connection.connected?(timeout: 5)).to be true

      expect { connection.shutdown }.to change(connection, :connected?).from(true).to(false)
    end

    it 'remains true through multiple connection errors until CONNECTION_ERRORS_REPORTING_THRESHOLD is reached' do
      error_event = Concurrent::Event.new
      allow(GoodJob).to receive(:_on_thread_error) { error_event.set }
      stub_const('GoodJob::DedicatedConnection::RECONNECT_INTERVAL', 0.1)
      stub_const('GoodJob::DedicatedConnection::CONNECTION_ERRORS_REPORTING_THRESHOLD', 3)

      faults = Concurrent::AtomicFixnum.new(0)
      connection.every(0.05) do
        faults.increment
        raise ActiveRecord::ConnectionNotEstablished
      end
      connection.start
      expect(connection.connected?(timeout: 5)).to be true

      expect(error_event.wait(5)).to be true
      expect(faults.value).to be >= 3
      expect(connection).not_to be_connected
    end
  end

  it 'executes a noop SQL query every KEEPALIVE_INTERVAL to keep the connection alive' do
    stub_const('GoodJob::DedicatedConnection::KEEPALIVE_INTERVAL', 0.1)
    connection.start
    original_keepalive = connection.instance_variable_get(:@last_keepalive_time)

    wait_until { expect(connection.instance_variable_get(:@last_keepalive_time)).to be > original_keepalive }
  end

  it 'runs hooks in the order they were attached, and disconnects after them' do
    events = Concurrent::Array.new
    connection.on_connect { events << :connect_first }
    connection.on_connect { events << :connect_second }
    connection.on_disconnect { |generation, replaced| events << [:disconnect, generation.value.active?, replaced] }
    connection.start
    wait_until { expect(events).to eq [:connect_first, :connect_second] }

    connection.shutdown
    expect(events.last).to eq [:disconnect, true, false]
  end

  describe '#shutdown' do
    it 'does not wait for blocked disconnect hooks beyond its timeout and FORCED_REMOVAL_TIMEOUT' do
      stub_const('GoodJob::Reactor::FORCED_REMOVAL_TIMEOUT', 0.3)
      release = Concurrent::Event.new
      connection.on_disconnect { release.wait(5) }
      connection.start
      expect(connection.connected?(timeout: 5)).to be true

      started_at = Time.current
      expect(connection.shutdown(timeout: nil)).to be false
      expect(connection.shutdown(timeout: 0.2)).to be false
      expect(Time.current - started_at).to be < 1
    ensure
      release.set
      wait_until { expect(connection).to be_shutdown }
    end
  end

  it 'starts again after the reactor fails' do
    allow(GoodJob).to receive(:_on_thread_error)
    connection.start
    expect(connection.connected?(timeout: 5)).to be true
    connection.reactor.loop.post { connection.reactor.fail!(RuntimeError.new("fail")) }
    wait_until { expect(connection).to be_shutdown }

    connection.start
    wait_until { expect(connection).to be_running }
    expect(connection.post { |conn| conn.select_value("SELECT 1") }.value!).to eq 1
  end

  it 'replaces a connection that faults while connecting' do
    stub_const('GoodJob::DedicatedConnection::RECONNECT_INTERVAL', 0.1)
    allow(GoodJob).to receive(:_on_thread_error)
    attempts = Concurrent::AtomicFixnum.new(0)
    connected = Concurrent::Event.new
    connection.on_connect do
      raise ActiveRecord::ConnectionNotEstablished if attempts.increment == 1

      connected.set
    end
    connection.start

    expect(connected.wait(5)).to be true
    expect(attempts.value).to eq 2
  end
end
