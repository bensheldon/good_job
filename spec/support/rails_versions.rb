RSpec.configure do |c|
  less_than_rails_6 = Gem::Version.new(Rails.version) < Gem::Version.new('6')
  c.filter_run_excluding(:skip_rails_5) if less_than_rails_6
end
