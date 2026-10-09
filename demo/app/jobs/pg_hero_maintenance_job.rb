class PgHeroMaintenanceJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  self.good_job_labels = ["pg_hero_maintenance"]
  good_job_concurrency_rule(
    label: "pg_hero_maintenance",
    total_limit: 1
  )

  discard_on StandardError

  def perform
    PgHero.capture_query_stats
    PgHero.clean_query_stats
  end
end
