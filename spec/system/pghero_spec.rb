# frozen_string_literal: true

require 'rails_helper'

describe 'PGHero', :demo_only do
  describe 'access' do
    context 'with the appropriate environment variables set' do
      before do
        allow(ENV).to receive(:[]).with('PGHERO_USERNAME').and_return('link')
        allow(ENV).to receive(:[]).with('PGHERO_PASSWORD').and_return('hyrule')
      end

      it 'fails without the basic auth credentials' do
        visit pg_hero_path

        expect(status_code).to eq 401
        expect(page).to have_content 'HTTP Basic: Access denied.'
      end

      it 'succeeds with the credentials' do
        # this will only work with the rack_test driver
        page.driver.browser.basic_authorize 'link', 'hyrule'

        visit pg_hero_path

        expect(status_code).to eq 200
        expect(page).to have_content 'PgHero'
      end
    end
  end
end
