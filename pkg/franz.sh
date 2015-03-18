#!/bin/bash
set -e
[ -z "$FRANZ_ROOT" -a -d franz ] && FRANZ_ROOT=franz
FRANZ_ROOT=${FRANZ_ROOT:-/opt/franz}
export BUNDLE_GEMFILE="$FRANZ_ROOT/vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG
exec "$FRANZ_ROOT/ruby/bin/ruby" -rbundler/setup "$FRANZ_ROOT/bin/franz" $@