# frozen_string_literal: true

require 'rails_helper'

describe "Demo Rack::Attack rules" do
  let(:job_id) { SecureRandom.uuid }

  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    example.run
  ensure
    Rack::Attack.reset!
    Rack::Attack.enabled = false
  end

  def get_as(path, ip:)
    get path, env: { "REMOTE_ADDR" => ip }
  end

  describe "job pages throttle" do
    it "limits each IP to 10 job page requests per minute" do
      10.times { get_as("/good_job/jobs/#{job_id}", ip: "1.1.1.1") }
      expect(response).not_to have_http_status(:too_many_requests)

      get_as("/good_job/jobs/#{job_id}", ip: "1.1.1.1")
      expect(response).to have_http_status(:too_many_requests)

      get_as("/good_job/jobs/#{job_id}", ip: "2.2.2.2")
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "does not throttle the jobs index" do
      11.times { get_as("/good_job/jobs", ip: "1.1.1.1") }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "action link ban" do
    it "bans an IP from all pages after a GET to an action URL" do
      get_as("/good_job/jobs/#{job_id}/force_discard", ip: "1.1.1.1")
      expect(response).to have_http_status(:forbidden)

      get_as("/good_job/jobs", ip: "1.1.1.1")
      expect(response).to have_http_status(:forbidden)

      get_as("/good_job/jobs", ip: "2.2.2.2")
      expect(response).to have_http_status(:ok)
    end

    it "lifts the ban after a minute" do
      get_as("/good_job/cron_entries/example/enqueue", ip: "1.1.1.1")

      Timecop.travel(61.seconds.from_now) do
        get_as("/good_job/jobs", ip: "1.1.1.1")
        expect(response).to have_http_status(:ok)
      end
    end

    it "does not ban the legitimate GET mass_update redirect" do
      get_as("/good_job/jobs/mass_update", ip: "1.1.1.1")
      get_as("/good_job/jobs", ip: "1.1.1.1")
      expect(response).to have_http_status(:ok)
    end
  end
end
