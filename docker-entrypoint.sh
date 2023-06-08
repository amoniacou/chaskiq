#!/bin/bash
set -e

if ! whoami &> /dev/null; then
    if [ -w /etc/passwd ]; then
        echo "${USER_NAME:-appuser}:x:$(id -u):0:${USER_NAME:-appuser} user:${APP_ROOT}:/sbin/nologin" >> /etc/passwd
    fi
fi

if [[ "$1" == "bundle" ]] || [[ "$1" == "yarn" ]] ||  [[ "$1" == "rails" ]]; then
  exec "$@"
fi


if [ -f /tmp/puma.pid ]; then
    echo "Cleanin server PID file"
    rm /tmp/puma.pid
fi

exec "$@"
