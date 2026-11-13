# The base image provides Ruby, the vscode user, nvm and build tools.
# The tag is <image version>-<Ruby version>-<Debian release>; its Ruby must
# match .ruby-version, which the Gemfile requires exactly.
ARG VARIANT="4-4.0-trixie"
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains
ENV RAILS_DEVELOPMENT_HOSTS=".app.github.dev"

ARG NODE_VERSION="lts/*"
RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"

# Install additional OS packages.
# The base image's Yarn apt source has an expired signing key; drop it.
RUN rm -f /etc/apt/sources.list.d/yarn* \
  && apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y install --no-install-recommends \
    chromium \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/*

# Task (taskfile.dev) runs the commands in Taskfile.yml.
# Checksums from the release's task_checksums.txt.
ARG TASK_VERSION="3.54.0"
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
    amd64) sha256="680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb" ;; \
    arm64) sha256="d7189d439d4a6058e39e1b2acd7c8b27acd4856691b408f23b242e4294e1df5b" ;; \
    *) echo "No Task checksum for $arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL -o /tmp/task.tar.gz "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_${arch}.tar.gz" \
  && echo "${sha256}  /tmp/task.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/task.tar.gz -C /usr/local/bin task \
  && rm /tmp/task.tar.gz

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
# Let postCreateCommand's bundle install, run as vscode, write to GEM_HOME.
RUN chown -R vscode:vscode "${GEM_HOME}"
