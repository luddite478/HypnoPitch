#!/usr/bin/env bash
# Build and upload HypnoPitch to Google Play (internal track) and/or App Store Connect (TestFlight).
#
#   ./deploy_stores.sh [store]
#     store: all (default) | app-store | google-play
#
# Prerequisites:
#   cd app/android && bundle install
#   cd app/ios && bundle install
#
# Google Play:
#   GOOGLE_PLAY_JSON_KEY_PATH      Filesystem path to the Google Play service-account JSON.
#
# App Store Connect / Apple:
#   FASTLANE_APPLE_ID              Apple ID email used for App Store Connect.
#   FASTLANE_ITC_TEAM_ID           App Store Connect team id.
#   FASTLANE_TEAM_ID               Apple Developer Portal team id.
#
#   APP_STORE_CONNECT_KEY_ID       Short Key ID from the .p8 row in App Store Connect (not the PEM).
#   APP_STORE_CONNECT_API_ISSUER   Issuer UUID from Users and Access → Keys → App Store Connect API.
#
#   Use exactly one of:
#     APP_STORE_CONNECT_P8_PATH       Filesystem path to AuthKey_XXXXXXXXXX.p8 (recommended).
#     APP_STORE_CONNECT_P8_CONTENT    Full PEM text of that file (contents), not the Key ID.
#
#   Legacy compatibility:
#     APP_STORE_CONNECT_API_KEY_PATH / APP_STORE_CONNECT_API_KEY are still accepted,
#     but they are remapped to the names above before Fastlane runs.
#
# Optional: DEPLOY_ENV_FILE=/path/to/env ./deploy_stores.sh (defaults to app/.env if present).
#
# Versioning: increments pubspec build number (+N) once before both builds so Android & iOS match.
# By default this script also bumps the marketing version by one patch version, e.g. 1.0.5+27 -> 1.0.6+28.
#   MARKETING_VERSION_BUMP=none|patch|minor|major   Override the marketing version bump strategy.
#   SKIP_VERSION_BUMP=1                              Do not bump (rebuild/re-upload same version; use with care).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load env file so Apple vars work without manual `export` (subprocesses only inherit exported vars).
ENV_FILE="${DEPLOY_ENV_FILE:-$SCRIPT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# CocoaPods on macOS can fail under non-UTF-8 locales during flutter build ipa.
# Default to a UTF-8 locale so both direct script usage and Fastlane child
# processes see a stable environment.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Fastlane treats APP_STORE_CONNECT_API_KEY_PATH as a JSON API key file path.
# Our setup uses a raw .p8 key, so remap legacy names to neutral ones before invoking Fastlane.
export APP_STORE_CONNECT_P8_PATH="${APP_STORE_CONNECT_P8_PATH:-${APP_STORE_CONNECT_API_KEY_PATH:-}}"
export APP_STORE_CONNECT_P8_CONTENT="${APP_STORE_CONNECT_P8_CONTENT:-${APP_STORE_CONNECT_API_KEY:-}}"
unset APP_STORE_CONNECT_API_KEY_PATH
unset APP_STORE_CONNECT_API_KEY

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,35p' "$0"
  printf '\nUsage: %s [store]\n  store: all (default) | app-store | google-play\n  Aliases: app-store (ios, apple); google-play (android, play); all (both)\n' "$(basename "$0")"
  exit 0
fi

STORE="${1:-all}"
case "$STORE" in
  all|both)
    RUN_GOOGLE=1
    RUN_APPLE=1
    ;;
  app-store|appstore|ios|apple)
    RUN_GOOGLE=0
    RUN_APPLE=1
    ;;
  google-play|googleplay|android|play)
    RUN_GOOGLE=1
    RUN_APPLE=0
    ;;
  *)
    echo "Unknown store '${STORE}'. Use: all, app-store, or google-play. Try --help." >&2
    exit 1
    ;;
esac

require_apple_env() {
  local missing=()
  if [[ -z "${FASTLANE_APPLE_ID:-}" ]]; then
    missing+=("FASTLANE_APPLE_ID")
  fi
  if [[ -z "${FASTLANE_ITC_TEAM_ID:-}" ]]; then
    missing+=("FASTLANE_ITC_TEAM_ID")
  fi
  if [[ -z "${FASTLANE_TEAM_ID:-}" ]]; then
    missing+=("FASTLANE_TEAM_ID")
  fi
  if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
    missing+=("APP_STORE_CONNECT_KEY_ID")
  fi
  if [[ -z "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
    missing+=("APP_STORE_CONNECT_API_ISSUER")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing: ${missing[*]}" >&2
    exit 1
  fi
  if [[ -z "${APP_STORE_CONNECT_P8_PATH:-}" && -z "${APP_STORE_CONNECT_P8_CONTENT:-}" ]]; then
    echo "Set APP_STORE_CONNECT_P8_PATH (path to .p8) or APP_STORE_CONNECT_P8_CONTENT (PEM contents)." >&2
    exit 1
  fi
  if [[ -n "${APP_STORE_CONNECT_P8_PATH:-}" && ! -f "${APP_STORE_CONNECT_P8_PATH}" ]]; then
    echo "APP_STORE_CONNECT_P8_PATH is not a file: ${APP_STORE_CONNECT_P8_PATH}" >&2
    exit 1
  fi
}

require_google_env() {
  if [[ -z "${GOOGLE_PLAY_JSON_KEY_PATH:-}" ]]; then
    echo "Missing: GOOGLE_PLAY_JSON_KEY_PATH" >&2
    exit 1
  fi
  if [[ ! -f "${GOOGLE_PLAY_JSON_KEY_PATH}" ]]; then
    echo "GOOGLE_PLAY_JSON_KEY_PATH is not a file: ${GOOGLE_PLAY_JSON_KEY_PATH}" >&2
    exit 1
  fi
}

if [[ "$RUN_GOOGLE" -eq 1 ]]; then
  require_google_env
fi
if [[ "$RUN_APPLE" -eq 1 ]]; then
  require_apple_env
fi

if [[ "${SKIP_VERSION_BUMP:-}" != "1" ]]; then
  MARKETING_VERSION_BUMP="${MARKETING_VERSION_BUMP:-patch}"
  echo "==> Bump pubspec version (marketing: ${MARKETING_VERSION_BUMP}, build: +1) [target: ${STORE}]"
  ruby "$SCRIPT_DIR/scripts/bump_pubspec_build.rb" "$SCRIPT_DIR/pubspec.yaml" "$MARKETING_VERSION_BUMP"
else
  echo "==> SKIP_VERSION_BUMP=1 — leaving pubspec version unchanged"
fi

if [[ "$RUN_GOOGLE" -eq 1 ]]; then
  echo "==> Google Play (Fastlane android build_prod)"
  ( cd "$SCRIPT_DIR/android" && bundle exec fastlane build_prod )
fi

if [[ "$RUN_APPLE" -eq 1 ]]; then
  echo "==> App Store Connect / TestFlight (fastlane ios release)"
  ( cd "$SCRIPT_DIR/ios" && bundle exec fastlane ios release )
fi

echo "Done."
