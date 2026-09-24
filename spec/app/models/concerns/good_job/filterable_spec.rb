# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Filterable do
  let(:model_class) { GoodJob::Job }
  let!(:job) do
    model_class.create!(
      active_job_id: SecureRandom.uuid,
      queue_name: "default",
      job_class: "ExampleJob",
      scheduled_at: Time.current,
      serialized_params: { example_key: 'example_value', arguments: ["hello-arg", 998899] },
      labels: %w[buffalo gopher],
      error: "ExampleJob::ExampleError: a message",
      error_event: "retried"
    )
  end

  describe '.search_test' do
    it 'searches serialized params' do
      expect(model_class.search_text('example_value')).to include(job)
    end

    it 'searches record id' do
      expect(model_class.search_text(job.id)).to include(job)
    end

    it 'searches active_job_id' do
      expect(model_class.search_text(job.active_job_id)).to include(job)
    end

    it 'searches labels' do
      expect(model_class.search_text('buffalo')).to include(job)
      expect(model_class.search_text('gopher')).to include(job)
      expect(model_class.search_text('hippo')).not_to include(job)
    end

    it 'searches errors' do
      expect(model_class.search_text('ExampleError')).to include(job)
    end

    it 'searches arguments, including numeric arguments' do
      expect(model_class.search_text('hello-arg')).to include(job)
      expect(model_class.search_text('998899')).to include(job)
    end

    it 'searches strings with colons' do
      expect(model_class.search_text('ExampleJob::ExampleError')).to include(job)
    end

    it 'filters out non-matching records' do
      expect(model_class.search_text('ghost')).to be_empty
    end

    context 'with identifier-like argument strings' do
      let!(:job) do
        model_class.create!(
          active_job_id: SecureRandom.uuid,
          queue_name: "default",
          job_class: "ExampleJob",
          scheduled_at: Time.current,
          serialized_params: {
            arguments: [{
              "ad_id" => "ad_qTB3kTjQeZEmptyx8JZ5",
              "ad_ref" => "A-1012679",
              "line_item_gid" => "gid://supply-side-platform/Orders::Types::ReservationLineItem/rli_Dd2LpagvXuqaZNAZt4yu",
              "purchase_order_id" => "po_8o9yOwc88sfMQWFmjE8F",
              "_aj_ruby2_keywords" => %w[purchase_order_id line_item_gid ad_ref ad_id],
            }],
          }
        )
      end

      it 'searches a nested URL-like identifier' do
        expect(model_class.search_text('gid://supply-side-platform/Orders::Types::ReservationLineItem/rli_Dd2LpagvXuqaZNAZt4yu')).to include(job)
      end

      it 'searches a substring of an identifier' do
        expect(model_class.search_text('rli_Dd2LpagvXuqaZNAZt4yu')).to include(job)
      end

      it 'searches an identifier with dashes' do
        expect(model_class.search_text('A-1012679')).to include(job)
      end
    end

    it 'does not raise when the error column exceeds the tsvector size limit' do
      # Many distinct tokens — repeated tokens collapse via tsvector dedup.
      oversized_error = "BoomError: #{Array.new(200_000) { |i| "w#{i}" }.join(' ')}"
      oversized_job = model_class.create!(
        active_job_id: SecureRandom.uuid,
        queue_name: "default",
        job_class: "ExampleJob",
        scheduled_at: Time.current,
        serialized_params: { arguments: [] },
        error: oversized_error,
        error_event: "retried"
      )

      expect { model_class.search_text('anything').to_a }.not_to raise_error
      expect(model_class.search_text('BoomError')).to include(oversized_job)
    end

    it 'is chainable and reversible' do
      expect(model_class.where.not(id: nil).search_text('example_value').reverse).to include(job)
    end

    it 'finds results when default_text_search_config is not english' do
      job_with_stemmed_word = model_class.create!(
        active_job_id: SecureRandom.uuid,
        queue_name: "default",
        job_class: "ExampleJob",
        scheduled_at: Time.current,
        serialized_params: { example_key: 'running', arguments: [] },
        error_event: "retried"
      )

      GoodJob::BaseRecord.lease_connection.execute("SET default_text_search_config = 'pg_catalog.simple'")
      begin
        expect(model_class.search_text('running')).to include(job_with_stemmed_word)
      ensure
        GoodJob::BaseRecord.lease_connection.execute("SET default_text_search_config = 'pg_catalog.english'")
      end
    end
  end
end
