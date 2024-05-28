# frozen_string_literal: true

module GoodJob
  class PerformancesJobClassChart
    attr_reader :job_class

    PERIOD = 1.day

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
            x: {
              display: false
            },
            y: {
              beginAtZero: true
            }
          },
          plugins: {
            legend: {
              display: false
            },
            tooltip: {
              enabled: false
            },
          }
        }
      }
    end

    protected

    def end_time
      @end_time ||= Time.current
    end

    def start_time
      @start_time ||= end_time - PERIOD
    end

    def datasets
      [
        {
          label: job_class,
          data: executions.map { |execution|
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

    def executions
      GoodJob::Execution.where(job_class: job_class)
                        .finished_between(start_time, end_time)
    end
  end
end
