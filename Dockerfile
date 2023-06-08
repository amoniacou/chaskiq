ARG RUBY_VERSION=3.2.0
ARG APP_ROOT=/app
ARG PG_MAJOR=14
ARG NODE_MAJOR=16
ARG BUNDLER_VERSION=2.3.26
ARG YARN_VERSION=1.22.4
ARG SYSTEM_PACKAGES="curl gnupg lsb-release"
ARG BUILD_PACKAGES="build-essential libpq-dev libxml2-dev libxslt1-dev libc6-dev shared-mime-info zlib1g-dev nodejs"
ARG DEV_PACKAGES="git unzip"
ARG RUBY_PACKAGES="tzdata postgresql-client-$PG_MAJOR libjemalloc2 libyaml-0-2"

FROM ruby:$RUBY_VERSION-slim-bullseye AS basic
ARG APP_ROOT
ARG BUILD_PACKAGES
ARG DEV_PACKAGES
ARG RUBY_PACKAGES
ARG SYSTEM_PACKAGES
ARG PG_MAJOR
ARG BUNDLER_VERSION
ARG YARN_VERSION
ARG NODE_MAJOR
ENV LANG=C.UTF-8 
ENV DEBIAN_FRONTEND noninteractive
ENV APP_ROOT=${APP_ROOT}
ENV PG_MAJOR=${PG_MAJOR}
ENV NODE_MAJOR=${NODE_MAJOR}
ENV YARN_VERSION=${YARN_VERSION}
ENV BUNDLER_VERSION=${BUNDLER_VERSION}
ENV SYSTEM_PACKAGES=${SYSTEM_PACKAGES}
ENV BUILD_PACKAGES=${BUILD_PACKAGES}
ENV DEV_PACKAGES=${DEV_PACKAGES}
ENV RUBY_PACKAGES=${RUBY_PACKAGES}
ENV HOME=${APP_ROOT}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh

ARG APP_ENV
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  --mount=type=tmpfs,target=/tmp \
  set -x && apt-get update && apt-get install --no-install-recommends --yes ${SYSTEM_PACKAGES} \
  && curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null \
  && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && sed -i "s/$(lsb_release -cs) main/$(lsb_release -cs) main contrib non-free/" /etc/apt/sources.list \
  && echo "deb http://http.debian.net/debian $(lsb_release -cs)-backports main contrib non-free" >> /etc/apt/sources.list \
  && curl -sL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash - \
  && apt-get update \
  && apt-get upgrade --yes \
  && apt-get install --no-install-recommends --yes ${BUILD_PACKAGES} \
  ${DEV_PACKAGES} \
  ${RUBY_PACKAGES} \
  && mkdir -p ${APP_ROOT} ${APP_ROOT}/vendor/bundle ${APP_ROOT}/.config && adduser --system --gid 0 --uid 1001 --home ${APP_ROOT} appuser \
  && mkdir /tmp/bundle && chgrp -R 0 /tmp/bundle && chmod -R g=u /tmp/bundle \
  && chgrp -R 0 ${APP_ROOT} && chmod -R g=u ${APP_ROOT} && chmod g=u /etc/passwd \
  && gem update --system && gem install bundler:$BUNDLER_VERSION && apt-get clean \
  && npm install -g yarn@$YARN_VERSION

# Set a user to run
USER 1001
ENTRYPOINT ["/docker-entrypoint.sh"]
# set working folder
WORKDIR $APP_ROOT

FROM basic AS dev
ENV RAILS_ENV=development
ENV BUNDLE_PATH /app/vendor/bundle
EXPOSE 3000
USER 1001
COPY --chown=1001:0 . .

# BUILD FOR PROD
FROM basic AS build-env
ENV RAILS_ENV=production
ENV BUNDLE_JOBS=4 BUNDLE_RETRY=3
# Cache Gemfiles and rebuild of it
COPY --chown=1001:0 Gemfile Gemfile.lock ./
RUN --mount=type=cache,id=chasiq-gem-cache,sharing=locked,target=$APP_ROOT/.cache/bundle,uid=1001 \
  set -x && bundle config --global frozen 1 \
  && bundle config set path /app/.cache/bundle \
  && bundle config set deployment "true" \
  && bundle config set without "test development" \
  && bundle install --jobs $BUNDLE_JOBS --retry $BUNDLE_RETRY \
  # Remove unneeded files (cached *.gem, *.o, *.c)
  && rm -rf vendor/bundle && mkdir -p vendor \
  && cp -ar .cache/bundle vendor/ \
  && bundle config set path /app/vendor/bundle \
  && rm -rf vendor/bundle/ruby/*/cache/*.gem \
  && find vendor/bundle/ruby/*/gems/ -name "*.c" -delete \
  && find vendor/bundle/ruby/*/gems/ -name "*.o" -delete
# cache node.js packages
COPY --chown=1001:0 package.json yarn.lock ./
COPY --chown=1001:0 app/javascript/packages ./app/javascript/packages
RUN --mount=type=cache,id=-yarn-cache,sharing=locked,target=/app/.yarn,uid=1001 \
  --mount=type=cache,id=-dot-cache,sharing=locked,target=/app/.cache,uid=1001 \
  --mount=type=tmpfs,target=/tmp \
  set -x && yarn install --frozen-lockfile --non-interactive
COPY --chown=1001:0 . .
# compile assets
RUN --mount=type=cache,id=-assets-cache,sharing=locked,target=/app/tmp/cache,uid=1001 \
  --mount=type=cache,id=-dot-cache,sharing=locked,target=/app/.cache,uid=1001 \
  --mount=type=tmpfs,target=/tmp \
  NODE_OPTIONS="--max-old-space-size=2048" \
  SECRET_KEY_BASE=`bin/rake secret` \
  bundle exec rails assets:precompile --trace \
  && rm -rf node_modules vendor/assets spec

# PRODUCTION BUILD
FROM basic AS production
COPY --chown=1001:0 --from=build-env $APP_ROOT $APP_ROOT
RUN bundle config set --local path './vendor/bundle' && bundle config set deployment "true" && bundle config set without "test development"
USER root
RUN set -x && DEBIAN_FRONTEND=noninteractive apt-get purge --auto-remove --yes ${SYSTEM_PACKAGES} ${BUILD_PACKAGES} ${DEV_PACKAGES} lib*-dev && rm -rf /var/lib/apt/*
USER 1001
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]