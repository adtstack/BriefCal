#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/verify_local_test_app.sh /path/to/BriefCal.app" >&2
  exit 64
fi

APP="$1"
INFO="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/BriefCal"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

test -d "$APP"
test -f "$INFO"
test -x "$EXECUTABLE"
test -d "$SPARKLE"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" = "com.adtstack.briefcal"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")" = "14.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :BriefCalLocalTestBuild' "$INFO")" = "YES"
test -z "$(find "$APP" \( -name '*.xctest' -o -name '*XCTest*' \) -print -quit)"

codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$EXECUTABLE" -verify_arch "$(uname -m)"

SIGNATURE_INFO="$(codesign -d --verbose=4 "$APP" 2>&1)"
if grep -Eq 'flags=.*runtime' <<<"$SIGNATURE_INFO"; then
  echo "Local-test app must not enable hardened runtime with ad-hoc signing." >&2
  exit 1
fi

VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/BriefCalLocalTest.XXXXXX")"
ENTITLEMENTS="$VERIFY_ROOT/entitlements.plist"
SMOKE_LOG="$VERIFY_ROOT/launch.log"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$VERIFY_ROOT"
}
trap cleanup EXIT

codesign -d --entitlements :- "$APP" 2>/dev/null > "$ENTITLEMENTS"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.calendars' "$ENTITLEMENTS")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.reminders' "$ENTITLEMENTS")" = "true"
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS" >/dev/null 2>&1; then
  echo "Local-test Release app must not contain get-task-allow." >&2
  exit 1
fi

env BRIEFCAL_UI_TEST_SCENARIO=baseline \
  "$EXECUTABLE" \
  --ui-testing \
  -ApplePersistenceIgnoreState YES \
  >"$SMOKE_LOG" 2>&1 &
APP_PID=$!

for _ in {1..12}; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    set +e
    wait "$APP_PID"
    STATUS=$?
    set -e
    APP_PID=""
    echo "BriefCal exited before the launch smoke interval completed (status $STATUS)." >&2
    sed -n '1,160p' "$SMOKE_LOG" >&2
    exit 1
  fi
  sleep 0.25
done

kill "$APP_PID"
set +e
wait "$APP_PID" 2>/dev/null
STATUS=$?
set -e
APP_PID=""

if [[ $STATUS -ne 0 && $STATUS -ne 143 ]]; then
  echo "BriefCal launch smoke ended unexpectedly (status $STATUS)." >&2
  sed -n '1,160p' "$SMOKE_LOG" >&2
  exit 1
fi

echo "Local-test app launch smoke passed: $APP"
