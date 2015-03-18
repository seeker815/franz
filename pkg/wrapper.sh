#!/bin/bash
set -e
SELFDIR="`dirname \"$0\"`"
SELFDIR="`cd \"$SELFDIR\" && pwd`"
[ -z "$FRANZ_ROOT" ] && ROOT="$SELFDIR/.franz"
[ -n "$FRANZ_ROOT" ] && ROOT="$FRANZ_ROOT"
export BUNDLE_GEMFILE="$ROOT/vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG
exec "$ROOT/ruby/bin/ruby" -rbundler/setup "$ROOT/app/bin/franz" $@
