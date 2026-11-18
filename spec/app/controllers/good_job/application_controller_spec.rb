# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::ApplicationController, type: :controller do
  render_views # seems required for Rails HEAD

  controller do
    def index
      render plain: "OK"
    end
  end

  describe "#current_locale" do
    it "defers to GET queries of params (to allow setting `mount...defaults: { locale: X })`" do
      allow(controller.params).to receive(:[]).with(:locale).and_return(:en)
      allow(controller.request.GET).to receive(:[]).with('locale').and_return(:de)

      expect(controller.send(:current_locale)).to eq(:de)
    end
  end

  describe "#use_good_job_locale" do
    around do |example|
      original_available_locales = I18n.available_locales
      original_default_locale = I18n.default_locale
      example.run
    ensure
      I18n.available_locales = original_available_locales
      I18n.default_locale = original_default_locale
    end

    it "does not leak I18n.available_locales written during a Dashboard request into the application" do
      I18n.available_locales = [:en, :"en-GB"]
      controller.define_singleton_method(:index) do
        # e.g. dry-schema runs this when its messages are first loaded
        I18n.available_locales |= [:en]
        render plain: "OK"
      end

      get :index

      expect(I18n.available_locales).to eq [:en, :"en-GB"]
    end

    it "does not leak I18n.default_locale written during a Dashboard request into the application" do
      I18n.default_locale = :en
      controller.define_singleton_method(:index) do
        I18n.default_locale = :de
        render plain: "OK"
      end

      get :index

      expect(I18n.default_locale).to eq :en
    end
  end
end
