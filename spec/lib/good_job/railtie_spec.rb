require 'rails_helper'

RSpec.describe GoodJob::Railtie do
  it 'copies over the Rails logger by default' do
    expect(GoodJob.logger).to eq Rails.logger
  end
end
