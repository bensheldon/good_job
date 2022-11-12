# frozen_string_literal: true
require 'rails_helper'

describe 'I18n Internationalization', js: true do
  describe "when changing language" do
    it "changes wording from English to Spanish" do
      visit good_job_path(locale: :en)

      expect(page).to have_content "Processes"
      find_by_id('localeOptions').click
      within ".navbar" do
        click_on "es"
      end
      expect(page).to have_content "Procesos"
    end

    it "changes wording from English to Ukrainian" do
      visit good_job_path(locale: :en)

      expect(page).to have_content "Processes"
      find_by_id('localeOptions').click
      within ".navbar" do
        click_on "ua"
      end
      expect(page).to have_content "Процеси"
    end
  end
end
