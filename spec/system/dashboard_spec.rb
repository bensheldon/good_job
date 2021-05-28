require 'rails_helper'

describe 'Dashboard', type: :system, js: true do
  it 'renders successfully' do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'
  end

  # This requires storing job in database, but rest of the tests is using inline adapter
  # Figure out how to workaround this
  xit 'deletes job' do
    ExampleJob.perform_later

    visit '/good_job'
    expect(page).to have_content 'ExampleJob'

    click_button('Delete job')
    expect(page).to have_content 'Job deleted'
    expect(page).not_to have_content 'ExampleJob'
  end
end
