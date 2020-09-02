require 'rails_helper'

describe 'Dashboard', type: :system, js: true do
  it 'renders successfully' do
    visit '/good_job'
    expect(page).to have_content 'Hello world!'
  end
end
