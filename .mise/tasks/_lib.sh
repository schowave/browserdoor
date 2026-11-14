# shellcheck shell=sh disable=SC2034
# Shared setup for the task scripts. They also run without mise (the Homebrew
# formula calls .mise/tasks/install directly), so they find the repo root themselves.
set -eu
cd "$(dirname "$0")/../.."
APP_NAME=Browserdoor
BUILD_DIR=build
REPO_URL=https://github.com/schowave/browserdoor
# SPARKLE=1 selects the download build (Sparkle, DMG); it lives in its own folder, so both
# builds can be made side by side.
SPARKLE="${SPARKLE:-0}"
if [ "$SPARKLE" = 1 ]; then
  APP="$BUILD_DIR/sparkle/$APP_NAME.app"
else
  APP="$BUILD_DIR/$APP_NAME.app"
fi
# Homebrew passes --disable-sandbox: its own sandbox forbids SwiftPM's.
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"
if [ -z "${VERSION:-}" ]; then
  VERSION="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.0.0}"
