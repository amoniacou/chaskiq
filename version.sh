#!/bin/sh
export BASE_VERSION=1.0.0
CURRENT_VERSION=$BASE_VERSION
if [[ "${GITHUB_HEAD_REF}" != "" ]]; then
  TASK_ID=$(echo ${GITHUB_HEAD_REF#refs/heads/} | tr '[:upper:]' '[:lower:]' | sed -E 's/^.*(amo-[0-9]+).*$/\1/g' | sed 's/-//g')
  CURRENT_VERSION="$BASE_VERSION-${TASK_ID}-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}"
  export APP_VERSION=$CURRENT_VERSION
else
  export APP_VERSION=$(echo $(git describe --exact-match --tags HEAD 2>/dev/null || echo "${CURRENT_VERSION}-$(git ls-files app lib config db config.ru public Dockerfile docker-entrypoint.sh yarn.lock Gemfile.lock | xargs sha256sum | sha256sum | cut -c 1-6 -)") | sed -e "s/^v//")
fi
