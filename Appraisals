ruby_2 = Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3')
ruby_27_or_higher = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')
jruby = RUBY_PLATFORM.include?('java')

if ruby_2
  appraise "rails-5.2" do
    gem "rails", "~> 5.2.0"
  end

  appraise "rails-6.0" do
    gem "rails", "~> 6.0.0"
  end
end

appraise "rails-6.1" do
  gem "rails", "~> 6.1.0"
end

if ruby_27_or_higher && !jruby
  # Rails HEAD requires MRI 2.7+
  # activerecord-jdbcpostgresql-adapter does not have a compatible version
  appraise "rails-head" do
    gem "rails", github: "rails/rails", branch: "main"
  end
end
