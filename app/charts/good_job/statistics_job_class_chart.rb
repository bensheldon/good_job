# frozen_string_literal: true

module GoodJob
  class StatisticsJobClassChart
    attr_reader :job_class

    def initialize(job_class)
      @job_class = job_class
    end

    def data
      {
        type: 'scatter',
        data: {
          datasets: datasets
        },
        options: {
          animation: 'animate',
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: {
              beginAtZero: true,
              title: 'Runtime'
            }
          },
          plugins: {
            legend: {
              display: false
            }
          }
        }
      }
    end

    protected

    def datasets
      [
        {
          label: job_class,
          data: GoodJob::Execution.where(job_class: job_class)
                                  .finished
                                  .map { |execution|
                                    [
                                      # Unix timestamp
                                      execution.finished_at.to_time.to_i,
                                      # Latency
                                      execution.runtime_latency
                                    ]
                                  }
        },
      ]
    end
  end
end
