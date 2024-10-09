# frozen_string_literal: true

ruby_30_or_higher = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.0')
ruby_31_or_higher = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1')
ruby_32_or_higher = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
jruby = RUBY_PLATFORM.include?('java')

unless ruby_31_or_higher # https://github.com/rails/rails/issues/44090#issuecomment-1007686519
  appraise "rails-6.1" do
    gem "rails", "~> 6.1.0"
    gem "traces", "~> 0.9.1"
    gem "puma", "~> 5.6"
  end
end

if ruby_30_or_higher && !ruby_31_or_higher && !jruby
  appraise "rails-7.0" do
    gem "rails", "~> 7.0.0"
  end
end

if ruby_31_or_higher
  appraise "rails-7.0-ruby-3.1" do
    gem "rails", "~> 7.0.1" # Ruby 3.1 requires Rails 7.0.1+
  end

  unless jruby
    appraise "rails-7.1-ruby-3.1" do
      gem "rails", "~> 7.1.0"
    end

    appraise "rails-7.2-ruby-3.1" do
      gem "rails", "~> 7.2.0"
    end
  end
end

if ruby_32_or_higher && !jruby
  appraise "rails-8.0-ruby-3.2" do
    gem "rails", "~> 8.0.0.a"
  end

  appraise "rails-head" do
    gem "rails", github: "rails/rails", branch: "main"
  end
end
