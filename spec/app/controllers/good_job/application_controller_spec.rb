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
end
