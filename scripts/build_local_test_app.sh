#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="${BRIEFCAL_LOCAL_DERIVED_DATA:-/private/tmp/BriefCalLocalTestDerivedData}"
APP="$DERIVED_DATA/Build/Products/Release/BriefCal.app"

BUILD_SETTINGS=(
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  ENABLE_HARDENED_RUNTIME=NO
  BRIEFCAL_LOCAL_TEST_BUILD=YES
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=BRIEFCAL_LOCAL_TEST_BUILD
  ONLY_ACTIVE_ARCH=NO
)

if [[ -n "${BRIEFCAL_MARKETING_VERSION:-}" ]]; then
  BUILD_SETTINGS+=("MARKETING_VERSION=$BRIEFCAL_MARKETING_VERSION")
fi
if [[ -n "${BRIEFCAL_CURRENT_PROJECT_VERSION:-}" ]]; then
  BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$BRIEFCAL_CURRENT_PROJECT_VERSION")
fi

cd "$REPOSITORY_ROOT"
xcodebuild -quiet \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  "${BUILD_SETTINGS[@]}" \
  build

bash "$SCRIPT_DIR/verify_local_test_app.sh" "$APP"

echo "Open this app to test BriefCal:"
echo "$APP"
