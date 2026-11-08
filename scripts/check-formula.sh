#!/bin/sh
# Sanity-checks the rendered formula: placeholders gone, make variables intact, valid Ruby.
set -eu
out="$("$(dirname "$0")/render-formula.sh" 9.8.7 0123abcd)"
fail() { echo "check-formula: $1" >&2; exit 1; }
echo "$out" | grep -q '@' && fail "unreplaced placeholder" || true
echo "$out" | grep -q 'refs/tags/v9.8.7.tar.gz' || fail "url not rendered"
echo "$out" | grep -q 'sha256 "0123abcd"' || fail "sha256 not rendered"
echo "$out" | grep -q '"VERSION=#{version}"' || fail "make VERSION argument damaged"
echo "$out" | ruby -c >/dev/null || fail "not valid Ruby"
echo "check-formula: ok"
