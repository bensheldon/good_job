# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ProbeServer::ClusterHealthcheckMiddleware do
  let(:app) { instance_double(Proc, call: nil) }
  let(:supervisor) { instance_double(GoodJob::Supervisor, started?: started, connected?: connected) }
  let(:started) { true }
  let(:connected) { true }
  let(:middleware) { described_class.new(app, supervisor) }
  let(:port) { 3434 }

  describe '#call' do
    let(:path) { nil }
    let(:env) { Rack::MockRequest.env_for("http://127.0.0.1:#{port}#{path}") }

    describe '/' do
      let(:path) { '/' }

      it 'returns 200 regardless of subprocess state' do
        expect(described_class.new(app, instance_double(GoodJob::Supervisor)).call(env)[0]).to eq(200)
      end
    end

    describe '/status/started' do
      let(:path) { '/status/started' }

      context 'when all subprocesses are running' do
        let(:started) { true }

        it 'returns 200' do
          expect(middleware.call(env)[0]).to eq(200)
        end
      end

      context 'when the cluster is not fully started' do
        let(:started) { false }

        it 'returns 503' do
          expect(middleware.call(env)[0]).to eq(503)
        end
      end
    end

    describe '/status/connected' do
      let(:path) { '/status/connected' }

      context 'when every subprocess is connected' do
        let(:connected) { true }

        it 'returns 200' do
          expect(middleware.call(env)[0]).to eq(200)
        end
      end

      context 'when a subprocess is not connected' do
        let(:connected) { false }

        it 'returns 503' do
          expect(middleware.call(env)[0]).to eq(503)
        end
      end
    end

    describe 'forwarding unknown requests to the given app' do
      let(:path) { '/unhandled_path' }

      it 'passes the request to the given app' do
        middleware.call(env)
        expect(app).to have_received(:call).with(env)
      end
    end
  end
end
