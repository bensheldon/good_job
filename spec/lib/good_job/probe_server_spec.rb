# frozen_string_literal: true

require 'rails_helper'
require 'net/http'

RSpec.describe GoodJob::ProbeServer do
  let(:port) { 3434 }

  describe '#start' do
    context "with default http server" do
      context 'with the default healthcheck app' do
        it 'starts a http server that binds to all interfaces and returns healthcheck responses' do
          probe_server = described_class.new(port: port)
          probe_server.start
          wait_until(max: 1) { expect(probe_server).to be_running }

          ip_addresses = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address)
          expect(ip_addresses.size).to be >= 2
          expect(ip_addresses).to include("127.0.0.1")

          aggregate_failures do
            ip_addresses.each do |ip_address|
              response = Net::HTTP.get(ip_address, "/", port)
              expect(response).to eq("OK")

              response = Net::HTTP.get(ip_address, "/status", port)
              expect(response).to eq("OK")

              response = Net::HTTP.get(ip_address, "/status/started", port)
              expect(response).to eq("Not started")

              response = Net::HTTP.get(ip_address, "/status/connected", port)
              expect(response).to eq("Not connected")

              response = Net::HTTP.get(ip_address, "/unimplemented_url", port)
              expect(response).to eq("Not found")
            end
          end

          probe_server.stop
        end
      end

      context 'with a provided app' do
        it 'starts a http server that binds to all interfaces and uses the supplied app' do
          app = proc { [200, { "Content-Type" => "text/plain" }, ["Hello World"]] }
          probe_server = described_class.new(app: app, port: port)
          probe_server.start
          wait_until(max: 1) { expect(probe_server).to be_running }

          ip_addresses = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address)
          expect(ip_addresses.size).to be >= 2
          expect(ip_addresses).to include("127.0.0.1")

          aggregate_failures do
            ip_addresses.each do |ip_address|
              response = Net::HTTP.get(ip_address, "/", port)
              expect(response).to eq("Hello World")
            end
          end

          probe_server.stop
        end
      end
    end

    context "with WEBrick" do
      context 'with the default healthcheck app' do
        it 'starts a WEBrick http server' do
          probe_server = described_class.new(port: port, handler: "webrick")
          probe_server.start
          wait_until(max: 1) { expect(probe_server).to be_running }

          ip_address = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address).first
          response = Net::HTTP.get_response(ip_address, "/", port)

          expect(response["server"]).to match(/WEBrick/)

          probe_server.stop
        end

        it 'server binds to all interfaces and returns healthcheck responses' do
          probe_server = described_class.new(port: port, handler: "webrick")
          probe_server.start
          wait_until(max: 1) { expect(probe_server).to be_running }

          ip_addresses = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address)
          expect(ip_addresses.size).to be >= 2
          expect(ip_addresses).to include("127.0.0.1")

          aggregate_failures do
            ip_addresses.each do |ip_address|
              response = Net::HTTP.get(ip_address, "/", port)
              expect(response).to eq("OK")

              response = Net::HTTP.get(ip_address, "/status", port)
              expect(response).to eq("OK")

              response = Net::HTTP.get(ip_address, "/status/started", port)
              expect(response).to eq("Not started")

              response = Net::HTTP.get(ip_address, "/status/connected", port)
              expect(response).to eq("Not connected")

              response = Net::HTTP.get(ip_address, "/unimplemented_url", port)
              expect(response).to eq("Not found")
            end
          end

          probe_server.stop
        end
      end

      context 'with a provided app' do
        it 'starts a http server that binds to all interfaces and uses the supplied app' do
          app = proc { [200, { "Content-Type" => "text/plain" }, ["Hello World"]] }
          probe_server = described_class.new(app: app, port: port)
          probe_server.start
          wait_until(max: 1) { expect(probe_server).to be_running }

          ip_addresses = Socket.ip_address_list.select(&:ipv4?).map(&:ip_address)
          expect(ip_addresses.size).to be >= 2
          expect(ip_addresses).to include("127.0.0.1")

          aggregate_failures do
            ip_addresses.each do |ip_address|
              response = Net::HTTP.get(ip_address, "/", port)
              expect(response).to eq("Hello World")
            end
          end

          probe_server.stop
        end
      end
    end
  end
end
