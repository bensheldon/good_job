# RAILS_ENV=production bundle exec ruby scripts/vernier.rb

require "vernier"
require_relative '../spec/test_app/config/environment'
require_relative '../lib/good_job'

Vernier.trace(out: "spec/test_app/tmp/vernier/good_job.json") do
  GoodJob.restart
  sleep 5
  GoodJob.shutdown
end
