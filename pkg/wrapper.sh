#!/bin/bash
set -e
SELFDIR="`dirname \"$0\"`"
SELFDIR="`cd \"$SELFDIR\" && pwd`"
export BUNDLE_GEMFILE="$SELFDIR/.vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG
exec "$SELFDIR/.ruby/bin/ruby" -rbundler/setup "$SELFDIR/.app/bin/franz" $@