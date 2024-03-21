class PgHeroMaintenanceJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    key: "pg_hero_maintenance",
    total_limit: 1
  )

  discard_on StandardError

  def perform
    PgHero.capture_query_stats
    PgHero.clean_query_stats
  end
end
