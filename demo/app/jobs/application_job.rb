class ApplicationJob < ActiveJob::Base
  include(
    GoodJob::ActiveJobExtensions::Concurrency,
    GoodJob::ActiveJobExtensions::Labels
  )

  POLYNOMIALLY_LONGER = if ActiveJob.gem_version >= Gem::Version.new("7.1.0.a")
                          :polynomially_longer
                        else
                          :exponentially_longer
                        end

  retry_on StandardError, wait: POLYNOMIALLY_LONGER, attempts: Float::INFINITY
end

