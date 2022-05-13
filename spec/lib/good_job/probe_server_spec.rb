# frozen_string_literal: true
require 'rails_helper'
require 'net/http'

RSpec.describe GoodJob::ProbeServer do
  let(:probe_server) { described_class.new(port: port) }
  let(:port) { 3434 }

  after do
    probe_server.stop
  end

  describe '#start' do
    it 'starts a webrick server that binds to all interfaces' do
      probe_server.start
      wait_until(max: 1) { expect(probe_server).to be_running }

      ip_addresses = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address)
      expect(ip_addresses.size).to be >= 2
      expect(ip_addresses).to include("127.0.0.1")

      aggregate_failures do
        ip_addresses.each do |ip_address|
          response = Net::HTTP.get(ip_address, "/", port)
          expect(response).to eq("OK")
        end
      end
    end
  end

  describe '#call' do
    let(:path) { nil }
    let(:env) { Rack::MockRequest.env_for("http://127.0.0.1:#{port}#{path}") }

    describe '/' do
      let(:path) { '/' }

      it 'returns "OK"' do
        response = probe_server.call(env)
        expect(response[0]).to eq(200)
      end
    end

    describe '/status/started' do
      let(:path) { '/status/started' }

      context 'when there are no running schedulers' do
        it 'returns 503' do
          response = probe_server.call(env)
          expect(response[0]).to eq(503)
        end
      end

      context 'when there are running schedulers' do
        it 'returns 200' do
          scheduler = instance_double(GoodJob::Scheduler, running?: true, shutdown: true, shutdown?: true)
          GoodJob::Scheduler.instances << scheduler

          response = probe_server.call(env)
          expect(response[0]).to eq(200)
        end
      end
    end

    describe '/status/connected' do
      let(:path) { '/status/connected' }

      context 'when there are no running schedulers or notifiers' do
        it 'returns 503' do
          response = probe_server.call(env)
          expect(response[0]).to eq(503)
        end
      end

      context 'when there are running schedulers and listening notifiers' do
        it 'returns 200' do
          scheduler = instance_double(GoodJob::Scheduler, running?: true, shutdown: true, shutdown?: true)
          GoodJob::Scheduler.instances << scheduler

          notifier = instance_double(GoodJob::Notifier, listening?: true, shutdown: true, shutdown?: true)
          GoodJob::Notifier.instances << notifier

          response = probe_server.call(env)
          expect(response[0]).to eq(200)
        end
      end
    end
  end
end
