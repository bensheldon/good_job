# [Choice] Ruby version: 3, 3.0, 2, 2.7, 2.6
ARG VARIANT="3"
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains
ENV RAILS_DEVELOPMENT_HOSTS=".githubpreview.dev,.app.github.dev"

ARG NODE_VERSION="lts/*"
RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"

# Add Chrome to Apt
RUN wget -q -O /tmp/linux_signing_key.pub https://dl-ssl.google.com/linux/linux_signing_key.pub \
  && apt-key add /tmp/linux_signing_key.pub \
  && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list

# Install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y install --no-install-recommends \
    chromium \
    chromium-driver \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

# Add Gemfile and install the gems. This means the gem install can be done
# during build instead of on start. When a fork or branch has different gems, we still have an
# advantage due to caching of the other gems.
RUN mkdir -p /tmp/good_job
COPY Gemfile Gemfile.lock good_job.gemspec /tmp/good_job/
RUN mkdir -p /tmp/good_job/lib/good_job
COPY lib/good_job/version.rb /tmp/good_job/lib/good_job
RUN cd /tmp/good_job \
    && bundle install \
    && rm -rf /tmp/good_job
RUN chown -R vscode:vscode /usr/local/rvm
