if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3')
  appraise "rails-5.2" do
    gem "rails", "~> 5.2.0"
  end

  appraise "rails-6.0" do
    gem "rails", "~> 6.0.0"
  end
end

appraise "rails-6.1" do
  gem "rails", "~> 6.1"
end

appraise "rails-head" do
  gem "rails", github: "rails/rails", branch: "master"
end
