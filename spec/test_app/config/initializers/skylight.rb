# frozen_string_literal: true

if defined?(Skylight)
  module SkylightSample
    CAPTURE_PERCENT = Integer(ENV.fetch("SKYLIGHT_SAMPLE_PERCENT", 100))

    def call(env)
      if rand(100) < CAPTURE_PERCENT
        super
      else
        @app.call(env)
      end
    end
  end

  Skylight::Middleware.prepend SkylightSample
end
