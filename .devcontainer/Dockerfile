# [Choice] Ruby version: 3, 3.0, 2, 2.7, 2.6
ARG VARIANT="3"
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains
ENV RAILS_DEVELOPMENT_HOSTS=".githubpreview.dev,.app.github.dev"

ARG NODE_VERSION="lts/*"
RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"

# Install additional OS packages.
# The base image's Yarn apt source has an expired signing key; drop it.
RUN rm -f /etc/apt/sources.list.d/yarn* \
  && apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y install --no-install-recommends \
    chromium \
    chromium-driver \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

# Ruby as pinned in .ruby-version; the base image ships an older one.
# Set as ENV directly: the base image's ENV RUBY_VERSION would override an ARG.
# Checksum from https://cache.ruby-lang.org/pub/ruby/index.txt
ENV RUBY_VERSION="4.0.9"
ARG RUBY_SHA256="a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4"
RUN cd /tmp \
  && curl -fsSL -o ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.xz" \
  && echo "${RUBY_SHA256}  ruby.tar.xz" | sha256sum -c - \
  && mkdir ruby-src && tar -xJf ruby.tar.xz -C ruby-src --strip-components=1 \
  && cd ruby-src \
  && ./configure --prefix=/usr/local --enable-shared --disable-install-doc \
  && make -j"$(nproc)" \
  && make install \
  && cd / && rm -rf /tmp/ruby.tar.xz /tmp/ruby-src

# Add Gemfile and install the gems. This means the gem install can be done
# during build instead of on start. When a fork or branch has different gems, we still have an
# advantage due to caching of the other gems.
RUN mkdir -p /tmp/good_job
COPY Gemfile Gemfile.lock good_job.gemspec .ruby-version /tmp/good_job/
RUN mkdir -p /tmp/good_job/lib/good_job
COPY lib/good_job/version.rb /tmp/good_job/lib/good_job
RUN cd /tmp/good_job \
    && bundle install \
    && rm -rf /tmp/good_job
RUN chown -R vscode:vscode /usr/local/rvm
