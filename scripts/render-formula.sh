#!/bin/sh
# Renders packaging/homebrew/doorman.rb for a release.
# Usage: scripts/render-formula.sh <version> <sha256>   (writes to stdout)
set -eu
version="$1"
sha="$2"
template="$(dirname "$0")/../packaging/homebrew/doorman.rb"
sed -e "s/@VERSION@/${version}/g" -e "s/@SHA256@/${sha}/g" -e '/^# /d' "$template"
