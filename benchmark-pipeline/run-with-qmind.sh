#!/usr/bin/env sh
set -eu

cp -a /opt/quantikmind-cli /tmp/quantikmind-cli
pip install --no-cache-dir /tmp/quantikmind-cli >/dev/null

exec "$@"
