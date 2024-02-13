# frozen_string_literal: true

require 'rails_helper'
require 'net/http'

RSpec.describe GoodJob::ProbeServer::HealthcheckMiddleware do
  let(:app) { instance_double(Proc, call: nil) }
  let(:healthcheck_middleware) { described_class.new(app) }
  let(:port) { 3434 }

  describe '#call' do
    let(:path) { nil }
    let(:env) { Rack::MockRequest.env_for("http://127.0.0.1:#{port}#{path}") }

    describe '/' do
      let(:path) { '/' }

      it 'returns "OK"' do
        response = healthcheck_middleware.call(env)
        expect(response[0]).to eq(200)
      end
    end

    describe '/status/started' do
      let(:path) { '/status/started' }

      context 'when there are no running schedulers' do
        it 'returns 503' do
          response = healthcheck_middleware.call(env)
          expect(response[0]).to eq(503)
        end
      end

      context 'when there are running schedulers' do
        it 'returns 200' do
          scheduler = instance_double(GoodJob::Scheduler, running?: true, shutdown: true, shutdown?: true)
          GoodJob::Scheduler.instances << scheduler

          response = healthcheck_middleware.call(env)
          expect(response[0]).to eq(200)
        end
      end
    end

    describe '/status/connected' do
      let(:path) { '/status/connected' }

      context 'when there are no running schedulers or notifiers' do
        it 'returns 503' do
          response = healthcheck_middleware.call(env)
          expect(response[0]).to eq(503)
        end
      end

      context 'when there are running schedulers but disconnected notifiers' do
        it 'returns 200' do
          scheduler = instance_double(GoodJob::Scheduler, running?: true, shutdown: true, shutdown?: true)
          GoodJob::Scheduler.instances << scheduler

          notifier = instance_double(GoodJob::Notifier, connected?: false, shutdown: true, shutdown?: true)
          GoodJob::Notifier.instances << notifier

          response = healthcheck_middleware.call(env)
          expect(response[0]).to eq(503)
        end
      end

      context 'when there are running schedulers and connected notifiers' do
        it 'returns 200' do
          scheduler = instance_double(GoodJob::Scheduler, running?: true, shutdown: true, shutdown?: true)
          GoodJob::Scheduler.instances << scheduler

          notifier = instance_double(GoodJob::Notifier, connected?: true, shutdown: true, shutdown?: true)
          GoodJob::Notifier.instances << notifier

          response = healthcheck_middleware.call(env)
          expect(response[0]).to eq(200)
        end
      end
    end

    describe 'forwarding unknown requests to given app' do
      let(:path) { '/unhandled_path' }

      it 'passes the request to the given app' do
        healthcheck_middleware.call(env)
        expect(app).to have_received(:call).with(env)
      end
    end
  end
end
