# frozen_string_literal: true

def current_ruby_version?(*versions)
  versions.any? do |v|
    version = Gem::Version.new(v)
    next_version = Gem::Version.new(Gem::Version.new(version).segments.tap { |s| s[1] += 1 }.join('.'))
    Gem::Version.new(RUBY_VERSION).between?(version, Gem::Version.new(version).segments.tap { |s| s[1] += 1 }.join('.'))
  end
end

jruby = RUBY_PLATFORM.include?('java')

if current_ruby_version?("2.7", "3.0")
  appraise "rails-6.0" do
    gem "rails", "~> 6.0.0"
  end

  appraise "rails-6.1" do
    gem "rails", "~> 6.1.0"
  end
end

if current_ruby_version?("3.0", "3.1", "3.2")
  appraise "rails-7.0" do
    gem "rails", "~> 7.0.0"
  end

  appraise "rails-head" do
    gem "rails", github: "rails/rails", branch: "main"
  end
end
