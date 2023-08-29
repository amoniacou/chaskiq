ARG RUBY_VERSION=3.2.2
ARG APP_ROOT=/app
ARG PG_MAJOR=14
ARG NODE_MAJOR=18
ARG BUNDLER_VERSION=2.4.17
ARG YARN_VERSION=1.22.4
ARG SYSTEM_PACKAGES="curl gnupg lsb-release"
ARG BUILD_PACKAGES="build-essential libpq-dev libxml2-dev libxslt1-dev libc6-dev shared-mime-info zlib1g-dev nodejs"
ARG DEV_PACKAGES="git unzip"
ARG RUBY_PACKAGES="tzdata postgresql-client-$PG_MAJOR libjemalloc2 libyaml-0-2"

FROM ruby:$RUBY_VERSION-slim-bookworm AS basic
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
  && sed -i "s/$(lsb_release -cs) main/$(lsb_release -cs) main contrib non-free/" /etc/apt/sources.list.d/debian.sources \
  && apt-get update \
  && apt-get upgrade --yes \
  && apt-get install --no-install-recommends --yes ${RUBY_PACKAGES} ${DEV_PACKAGES} ${BUILD_PACKAGES} \
  && mkdir -p ${APP_ROOT} ${APP_ROOT}/vendor/bundle ${APP_ROOT}/.config ${APP_ROOT}/.bundle && adduser --system --gid 0 --uid 10001 --home ${APP_ROOT} appuser \
  && mkdir /tmp/bundle && chgrp -R 0 /tmp/bundle && chmod -R g=u /tmp/bundle \
  && chgrp -R 0 ${APP_ROOT} && chmod -R g=u ${APP_ROOT} && chmod g=u /etc/passwd 

# Set a user to run
USER 10001
ENTRYPOINT ["/docker-entrypoint.sh"]
# set working folder
WORKDIR $APP_ROOT

FROM basic AS dev
ENV RAILS_ENV=development
ENV BUNDLE_PATH /app/vendor/bundle
EXPOSE 3000
USER 10001
COPY --chown=10001:0 . .

# BUILD FOR PROD
FROM basic AS build-env
ENV RAILS_ENV=production
ENV BUNDLE_RETRY=3
USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  --mount=type=tmpfs,target=/tmp \
  set -x \
  && curl -sL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash - \
  && apt-get update \
  && apt-get upgrade --yes \
  && apt-get install --no-install-recommends --yes ${BUILD_PACKAGES} ${DEV_PACKAGES} \
  && gem update --system && gem install bundler:$BUNDLER_VERSION && apt-get clean \
  && npm install -g yarn@$YARN_VERSION
# Cache Gemfiles and rebuild of it
USER 10001
COPY --chown=10001:0 Gemfile Gemfile.lock ./
RUN --mount=type=cache,id=chasiq-dot-cache,sharing=locked,target=$APP_ROOT/.cache,uid=10001 \
  --mount=type=cache,id=bundle-cache,sharing=locked,target=$APP_ROOT/.bundle/cache,uid=10001 \
  set -x && bundle config --global frozen 1 \
  && bundle config set path /app/.cache/bundle \
  && bundle config set deployment "true" \
  && bundle config set without "test development" \
  && bundle install --retry $BUNDLE_RETRY \
  # Remove unneeded files (cached *.gem, *.o, *.c)
  && rm -rf vendor/bundle && mkdir -p vendor \
  && cp -ar .cache/bundle vendor/ \
  && bundle config set path /app/vendor/bundle \
  && rm -rf vendor/bundle/ruby/*/cache \
  && find vendor/bundle/ruby/*/gems/ -name "*.c" -delete \
  && find vendor/bundle/ruby/*/gems/ -name "*.o" -delete \
  && find vendor/bundle/ruby/*/gems/ -name "*.a" -exec strip '{}' \; \
  && rm -rf vendor/bundle/ruby/*/gems/grpc-*/src/ruby/ext/grpc/objs
# cache node.js packages
COPY --chown=10001:0 package.json yarn.lock ./
COPY --chown=10001:0 app/javascript/packages ./app/javascript/packages
RUN --mount=type=cache,id=-yarn-cache,sharing=locked,target=/app/.yarn,uid=10001 \
  --mount=type=cache,id=-dot-cache,sharing=locked,target=/app/.cache,uid=10001 \
  --mount=type=tmpfs,target=/tmp \
  set -x && yarn install --frozen-lockfile --non-interactive
COPY --chown=10001:0 . .
# compile assets
RUN --mount=type=cache,id=-assets-cache,sharing=locked,target=/app/tmp/cache,uid=10001 \
  --mount=type=cache,id=-dot-cache,sharing=locked,target=/app/.cache,uid=10001 \
  --mount=type=tmpfs,target=/tmp \
  NODE_OPTIONS="--max-old-space-size=2048" \
  SECRET_KEY_BASE=`bin/rake secret` \
  bundle exec rails assets:precompile --trace \
  && rm -rf node_modules vendor/assets spec app/assets/builds app/javascript \
  && rm -rf vendor/bundle/ruby/*/gems/tailwindcss*/exe/*

# PRODUCTION BUILD
FROM basic AS production
COPY --chown=10001:0 --from=build-env $APP_ROOT $APP_ROOT
RUN set -x && rm -rf ./.* && bundle config set --local path './vendor/bundle' && bundle config set deployment "true" && bundle config set without "test development"
USER root
RUN set -x && DEBIAN_FRONTEND=noninteractive apt-get purge --auto-remove --yes ${SYSTEM_PACKAGES} && rm -rf /usr/include/* /var/lib/apt/* /var/cache/debconf
USER 10001
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
