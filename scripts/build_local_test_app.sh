#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="${KAOSCAL_LOCAL_DERIVED_DATA:-/private/tmp/KaosCalLocalTestDerivedData}"
APP="$DERIVED_DATA/Build/Products/Release/KaosCal.app"

BUILD_SETTINGS=(
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  ENABLE_HARDENED_RUNTIME=NO
  KAOSCAL_LOCAL_TEST_BUILD=YES
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=KAOSCAL_LOCAL_TEST_BUILD
  ONLY_ACTIVE_ARCH=NO
)

if [[ -n "${KAOSCAL_MARKETING_VERSION:-}" ]]; then
  BUILD_SETTINGS+=("MARKETING_VERSION=$KAOSCAL_MARKETING_VERSION")
fi
if [[ -n "${KAOSCAL_CURRENT_PROJECT_VERSION:-}" ]]; then
  BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$KAOSCAL_CURRENT_PROJECT_VERSION")
fi

cd "$REPOSITORY_ROOT"
xcodebuild -quiet \
  -project KaosCal.xcodeproj \
  -scheme KaosCal \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  "${BUILD_SETTINGS[@]}" \
  build

bash "$SCRIPT_DIR/verify_local_test_app.sh" "$APP"

echo "Open this app to test KaosCal:"
echo "$APP"
