# shellcheck shell=sh disable=SC2034
# Shared setup for the task scripts. They also run without mise (the Homebrew
# formula calls .mise/tasks/install directly), so they find the repo root themselves.
set -eu
cd "$(dirname "$0")/../.."
APP_NAME=Doorman
BUILD_DIR=build
APP="$BUILD_DIR/$APP_NAME.app"
# Homebrew passes --disable-sandbox: its own sandbox forbids SwiftPM's.
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"
if [ -z "${VERSION:-}" ]; then
  VERSION="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.0.0}"
