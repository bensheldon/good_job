# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::LatencyMetric do
  describe ".from_params" do
    it "selects a metric by its key" do
      expect(described_class.from_params(chart: "queue")).to be_a(described_class::Queue)
      expect(described_class.from_params(chart: "execution")).to be_a(described_class::Execution)
    end

    it "reads the key out of request parameters, which arrive string-keyed" do
      params = ActionController::Parameters.new("chart" => "queue")

      expect(described_class.from_params(params)).to be_a(described_class::Queue)
    end

    it "falls back to the default for unrecognized, non-scalar, and blank input" do
      [
        { chart: "unknown" },
        { chart: ["queue"] },
        { chart: { value: "queue" } },
        { chart: "" },
        { chart: nil },
        {},
      ].each do |params|
        expect(described_class.from_params(params)).to be_a(described_class::Execution)
      end
    end
  end

  describe ".options" do
    it "lists every metric in toggle order, starting with the default" do
      expect(described_class.options.map(&:key)).to eq(%i[execution queue total])
      expect(described_class.options.map(&:key).first).to eq(described_class.default.key)
    end
  end

  describe ".table_aggregates_sql" do
    it "selects job and execution counts plus avg/min/max of queue, execution and total latency" do
      expect(described_class.table_aggregates_sql).to eq(
        "COUNT(DISTINCT active_job_id) AS jobs_count, COUNT(*) AS executions_count, " \
        "AVG((created_at - scheduled_at)) AS avg_queue, MIN((created_at - scheduled_at)) AS min_queue, " \
        "MAX((created_at - scheduled_at)) AS max_queue, " \
        "AVG(duration) AS avg_execution, MIN(duration) AS min_execution, MAX(duration) AS max_execution, " \
        "AVG(((created_at - scheduled_at) + duration)) AS avg_total, " \
        "MIN(((created_at - scheduled_at) + duration)) AS min_total, " \
        "MAX(((created_at - scheduled_at) + duration)) AS max_total"
      )
    end
  end

  describe described_class::Total do
    subject(:metric) { described_class.new }

    it "averages the queue wait plus the run time" do
      expect(metric.key).to eq(:total)
      expect(metric.expression).to eq("((created_at - scheduled_at) + duration)")
      expect(metric.aggregate).to eq("AVG")
      expect(metric.presence_sql).to eq("scheduled_at IS NOT NULL AND duration IS NOT NULL")
    end

    it "leaves an empty bucket as a spanned gap rather than claiming zero time" do
      expect(metric.empty_value).to be_nil
      expect(metric).to be_span_gaps
    end

    it "names itself in navigation URLs" do
      expect(metric.to_params).to eq(chart: "total")
    end

    it "titles the charts for total time" do
      expect(metric.chart_title).to eq("Average total latency in seconds")
      expect(metric.histogram_title).to eq("Total latency")
    end

    it "measures Execution#queue_latency plus #runtime_latency, and nothing while still running" do
      scheduled_at = Time.zone.parse("2024-01-01 10:00:00 UTC")
      execution = GoodJob::Execution.create!(
        active_job_id: SecureRandom.uuid,
        created_at: scheduled_at + 30.seconds,
        duration: 1.second,
        job_class: "ExampleJob",
        queue_name: "default",
        scheduled_at: scheduled_at,
        serialized_params: {},
        updated_at: scheduled_at
      )
      measure = lambda do
        GoodJob::Execution
          .where(id: execution.id)
          .pick(metric.to_arel.as("total"))
      end

      expect(measure.call).to eq(execution.queue_latency + execution.runtime_latency)
      expect(measure.call).to eq(31.seconds)

      execution.update!(duration: nil)

      expect(measure.call).to be_nil
    end
  end

  describe described_class::Execution do
    subject(:metric) { described_class.new }

    it "sums monotonic runtime" do
      expect(metric.key).to eq(:execution)
      expect(metric.expression).to eq("duration")
      expect(metric.to_arel).to be_a(Arel::Nodes::SqlLiteral).and eq("duration")
      expect(metric.aggregate).to eq("SUM")
      expect(metric.presence_sql).to eq("duration IS NOT NULL")
    end

    it "treats an empty bucket as zero work and needs no gap spanning" do
      expect(metric.empty_value).to eq(0)
      expect(metric).not_to be_span_gaps
    end

    it "stays out of navigation URLs as the default metric" do
      expect(metric.to_params).to eq({})
    end

    it "titles the charts for execution time" do
      expect(metric.chart_title).to eq("Total execution latency in seconds")
      expect(metric.histogram_title).to eq("Execution latency")
    end
  end

  describe described_class::Queue do
    subject(:metric) { described_class.new }

    it "averages the wait between scheduling and performing" do
      expect(metric.key).to eq(:queue)
      expect(metric.expression).to eq("(created_at - scheduled_at)")
      expect(metric.aggregate).to eq("AVG")
      expect(metric.presence_sql).to eq("scheduled_at IS NOT NULL")
    end

    it "leaves an empty bucket as a spanned gap rather than claiming zero wait" do
      expect(metric.empty_value).to be_nil
      expect(metric).to be_span_gaps
    end

    it "names itself in navigation URLs" do
      expect(metric.to_params).to eq(chart: "queue")
    end

    it "titles the charts for queue time" do
      expect(metric.chart_title).to eq("Average queue latency in seconds")
      expect(metric.histogram_title).to eq("Queue latency")
    end

    it "resolves titles in the request locale" do
      I18n.with_locale(:de) do
        expect(metric.chart_title).to eq("Durchschnittliche Warteschlangenlatenz in Sekunden")
        expect(metric.histogram_title).to eq("Warteschlangenlatenz")
      end
    end

    it "measures the same quantity as Execution#queue_latency" do
      scheduled_at = Time.zone.parse("2024-01-01 10:00:00 UTC")
      execution = GoodJob::Execution.create!(
        active_job_id: SecureRandom.uuid,
        created_at: scheduled_at + 30.seconds,
        duration: 1.second,
        job_class: "ExampleJob",
        queue_name: "default",
        scheduled_at: scheduled_at,
        serialized_params: {},
        updated_at: scheduled_at
      )

      measured = GoodJob::Execution
                 .where(id: execution.id)
                 .pick(metric.to_arel.as("queue"))

      expect(measured).to eq(execution.queue_latency)
      expect(measured).to eq(30.seconds)
    end
  end
end
