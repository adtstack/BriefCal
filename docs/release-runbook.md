# Release Runbook

이 문서는 KaosCal을 Mac App Store 밖에서 배포할 때 사용할 release 절차다. 명령은
저장소 root에서 실행한다. Apple Team, 인증서 이름, notary profile, 배포 URL 같은 값은
저장소에 아직 결정되어 있지 않으므로 환경변수로만 받는다. 자격 증명과 private key는
저장소, shell script, build log, release note에 기록하지 않는다.

관련 제품 정책은 [distribution.md](distribution.md), 현재 구현·최신 증거·열린 gate는
[current-status.md](current-status.md), 상세 검증 절차는 [qa-checklist.md](qa-checklist.md),
로컬 데이터 복구 경계는 [backup-restore.md](backup-restore.md)를 따른다.

## 현재 증거와 배포 차단선

이 runbook을 처음 작성한 Phase 9 checkpoint에서 확인된 것은 다음 범위까지다. 최신 판정은
[Current Status](current-status.md)를 우선하며 이 목록을 현재 상태 요약으로 사용하지 않는다.

- macOS 14.0 minimum, bundle identifier `com.adtstack.kaoscal`, 현재 project version
  `0.1.0` / build `1`
- pinned SwiftPM dependency를 사용한 Debug test와 Release build
- ad-hoc signed Release의 hardened runtime, strict code-signature, sandbox·Calendar·
  user-selected read/write entitlement, `get-task-allow` 부재
- exact ad-hoc Release 실행과 운영 DB 무변경 checkpoint

위 결과는 로컬 검증용이며 사용자에게 배포 가능한 서명이나 notarization 증거가 아니다.
아래 항목은 **외부 beta 전 필수이며 아직 통과로 기록할 수 없다.**

- 확정된 Apple Developer Team과 Keychain의 `Developer ID Application` identity
- 배포용 certificate/private key 관리 책임자와 폐기·교체 절차
- 검증된 `notarytool` Keychain profile
- Developer ID로 export한 app의 서명·secure timestamp 검증
- Apple notary service의 `Accepted` 결과, log 검토와 stapling
- 최종 ZIP 또는 DMG 형식과 실제 배포 위치
- quarantine이 유지되는 실제 다운로드 경로의 clean-user smoke
- [PRIVACY.md](../PRIVACY.md)와 [SECURITY.md](../SECURITY.md)의 미정 법적 주체·연락처,
  [beta license placeholder](../BETA-LICENSE.md)를 대체할 KaosCal license/EULA와 rollback
  공지 경로 확정
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)의 최종 dependency/license 재검증과
  배포물 포함

하나라도 준비되지 않으면 private beta artifact를 공개하지 않는다. 실패한 Developer ID
절차를 ad-hoc signature나 Gatekeeper 우회 안내로 대체하지 않는다.

## 1. Release 입력과 source 고정

먼저 release 담당자가 아래 값을 shell에 직접 설정한다. 예시 Team ID, 인증서 이름,
notary profile을 이 문서나 저장소에 채워 넣지 않는다.

```sh
export VERSION=''
export BUILD=''
export DEVELOPMENT_TEAM=''
export DEVELOPER_ID_APPLICATION=''
export NOTARY_PROFILE=''

: "${VERSION:?Set VERSION to the approved marketing version}"
: "${BUILD:?Set BUILD to a unique monotonically increasing build number}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM from the Apple developer account}"
: "${DEVELOPER_ID_APPLICATION:?Set the exact Developer ID Application identity name}"
: "${NOTARY_PROFILE:?Set the validated notarytool Keychain profile name}"

export RELEASE_ROOT="/private/tmp/KaosCal-release-${VERSION}-${BUILD}-$(date +%Y%m%d-%H%M%S)"
export DERIVED_DATA="$RELEASE_ROOT/DerivedData"
export ARCHIVE_PATH="$RELEASE_ROOT/KaosCal.xcarchive"
export EXPORT_PATH="$RELEASE_ROOT/export"
export DIST_PATH="$RELEASE_ROOT/dist"
mkdir -p "$DIST_PATH"
```

Release 입력을 검토한다.

```sh
xcodebuild -version
git status --short --branch
git rev-parse HEAD
security find-identity -v -p codesigning
```

다음을 모두 확인한 뒤 계속한다.

- worktree가 clean이고 release commit과 tag 후보가 review된 상태다.
- `VERSION`은 [CHANGELOG.md](../CHANGELOG.md)의 release 항목과 일치한다.
- `BUILD`은 이전 배포보다 큰 고유 정수다.
- `DEVELOPER_ID_APPLICATION`은 위 identity 목록의 정확한 `Developer ID Application`
  항목이다. `Apple Development`, `Mac Development`, ad-hoc identity가 아니다.
- [Package.resolved](../KaosCal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)가
  review된 상태이며 package update가 섞이지 않았다.
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)의 release gate를 다시 수행했다.

`MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`은 아래 archive 명령에서 명시적으로
고정한다. 정식 release commit에도 같은 값을 project build settings에 반영하고 diff를
review해야 한다. CLI override만 한 임시 archive를 source-of-truth로 남기지 않는다.

## 2. 자동 테스트와 현재 가능한 ad-hoc Release 검증

먼저 서명 없이 전체 Debug suite를 실행한다. 기본 suite에서 read-only EventKit 수동
test 하나가 opt-in skip되는 것은 의도된 동작이며, 다른 skip이나 failure는 허용하지
않는다.

```sh
xcodebuild \
  -project KaosCal.xcodeproj \
  -scheme KaosCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RELEASE_ROOT/KaosCalTests.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  test
```

그 다음 현재까지의 checkpoint와 같은 ad-hoc Release를 별도 Derived Data에 만든다.
이 app은 release 후보의 entitlement와 runtime을 조기에 검사하기 위한 것이며 배포물이
아니다.

```sh
export ADHOC_DERIVED_DATA="$RELEASE_ROOT/AdHocDerivedData"
export ADHOC_APP="$ADHOC_DERIVED_DATA/Build/Products/Release/KaosCal.app"

xcodebuild \
  -project KaosCal.xcodeproj \
  -scheme KaosCal \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$ADHOC_DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  build

codesign --verify --deep --strict --verbose=2 "$ADHOC_APP"
codesign -d --verbose=4 "$ADHOC_APP"
codesign -d --entitlements - "$ADHOC_APP"
```

출력에서 hardened runtime과 현재 세 entitlement를 확인하고
`com.apple.security.get-task-allow`가 없는지 확인한다. ad-hoc 검증의 성공을 아래
Developer ID 단계의 성공으로 기록하지 않는다.

## 3. Developer ID archive와 export

이 단계부터는 Apple Developer Program 접근, 설치된 certificate/private key와 network가
필요하다. 준비되지 않았다면 여기서 release를 중단한다.

```sh
xcodebuild \
  -project KaosCal.xcodeproj \
  -scheme KaosCal \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive
```

Developer ID export options를 release 임시 폴더에 만든다. 이 plist에는 secret을 넣지
않는다.

```sh
export EXPORT_OPTIONS="$RELEASE_ROOT/ExportOptions.plist"
plutil -create xml1 "$EXPORT_OPTIONS"
plutil -insert method -string developer-id "$EXPORT_OPTIONS"
plutil -insert destination -string export "$EXPORT_OPTIONS"
plutil -insert signingStyle -string manual "$EXPORT_OPTIONS"
plutil -insert signingCertificate -string "$DEVELOPER_ID_APPLICATION" "$EXPORT_OPTIONS"
plutil -insert teamID -string "$DEVELOPMENT_TEAM" "$EXPORT_OPTIONS"
plutil -insert stripSwiftSymbols -bool YES "$EXPORT_OPTIONS"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

export APP_PATH="$EXPORT_PATH/KaosCal.app"
test -d "$APP_PATH"
```

자동 signing을 사용하기로 별도 결정했다면 Xcode Organizer의 Developer ID export를
사용할 수 있지만, 그 선택과 실제 Team/certificate를 release record에 남긴다. signing
오류를 해결하려고 entitlement를 제거하거나 identity 종류를 낮추지 않는다.

## 4. 서명·버전·payload 검증

```sh
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --verbose=4 "$APP_PATH"
codesign -d --entitlements - "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist"

find "$APP_PATH" -name '*.xctest' -o -name '*XCTest*'
otool -L "$APP_PATH/Contents/MacOS/KaosCal"
```

통과 기준은 다음과 같다.

- signature chain의 leaf가 지정한 `Developer ID Application`이고 secure timestamp와
  runtime flag가 보인다.
- bundle/version/build/minimum이 각각 승인된 값, `com.adtstack.kaoscal`, macOS 14.0과
  일치한다.
- entitlement는 app sandbox, Calendar access, user-selected read/write만 의도대로
  포함하며 `get-task-allow`는 없다.
- XCTest bundle/link가 배포 app에 없다.
- `THIRD_PARTY_NOTICES.md`를 배포물에서 제공하기로 정한 위치가 실제 package에 있다.

Notarization 전 `spctl` 결과는 host cache나 아직 없는 ticket 때문에 최종 판정이 아닐 수
있다. signature 자체가 strict verification에 실패하면 notarization으로 진행하지 않는다.

## 5. Notarization과 stapling

notary profile은 한 번만 Keychain에 저장한다. 이 명령은 release script나 CI log가 아닌
신뢰하는 terminal에서 대화형으로 실행하며 password/private key를 인자로 남기지 않는다.

```sh
xcrun notarytool store-credentials "$NOTARY_PROFILE"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE"
```

`.app` bundle은 직접 submit하지 않고 임시 ZIP으로 감싼다.

```sh
set -euo pipefail
export NOTARY_UPLOAD="$RELEASE_ROOT/KaosCal-${VERSION}-${BUILD}-notary.zip"
export NOTARY_SUBMIT_JSON="$RELEASE_ROOT/notary-submit.json"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_UPLOAD"

xcrun notarytool submit "$NOTARY_UPLOAD" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_SUBMIT_JSON"

export SUBMISSION_ID="$(plutil -extract id raw -o - "$NOTARY_SUBMIT_JSON")"
export NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_SUBMIT_JSON")"
test "$NOTARY_STATUS" = "Accepted"

xcrun notarytool log \
  --keychain-profile "$NOTARY_PROFILE" \
  "$SUBMISSION_ID" \
  "$RELEASE_ROOT/notary-log.json"

xcrun stapler staple -v "$APP_PATH"
xcrun stapler validate -v "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
```

JSON의 submission ID와 `Accepted` 상태를 release record에 남긴다. 위 block은 status가
`Accepted`가 아니면 stapling 전에 중단된다. timeout, warning이 있거나 상태를 판정할 수
없으면 배포하지 않으며 Accepted인 경우에도 내려받은 log의 warning을 검토한다.

## 6. 최종 package와 checksum

ZIP과 DMG 중 실제 배포 형식을 하나 정한다. 둘 다 배포하면 둘 다 독립적으로 검증하고
release record에 남긴다.

### ZIP

stapled app을 새 ZIP으로 만든다. notarization upload용 ZIP을 그대로 배포하지 않는다.

```sh
export FINAL_ZIP="$DIST_PATH/KaosCal-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"
ditto -x -k "$FINAL_ZIP" "$RELEASE_ROOT/zip-smoke"
codesign --verify --deep --strict --verbose=2 "$RELEASE_ROOT/zip-smoke/KaosCal.app"
xcrun stapler validate -v "$RELEASE_ROOT/zip-smoke/KaosCal.app"
```

### DMG

DMG를 선택하면 stapled app으로 image를 만든 다음 DMG 자체도 submit하고 staple한다.

```sh
export DMG_ROOT="$RELEASE_ROOT/dmg-root"
export FINAL_DMG="$DIST_PATH/KaosCal-${VERSION}.dmg"
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/KaosCal.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "KaosCal ${VERSION}" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  "$FINAL_DMG"

codesign --force --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$FINAL_DMG"
codesign --verify --verbose=4 "$FINAL_DMG"

set -euo pipefail
export DMG_NOTARY_JSON="$RELEASE_ROOT/notary-dmg-submit.json"
xcrun notarytool submit "$FINAL_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$DMG_NOTARY_JSON"

export DMG_SUBMISSION_ID="$(plutil -extract id raw -o - "$DMG_NOTARY_JSON")"
export DMG_NOTARY_STATUS="$(plutil -extract status raw -o - "$DMG_NOTARY_JSON")"
test "$DMG_NOTARY_STATUS" = "Accepted"

xcrun notarytool log \
  --keychain-profile "$NOTARY_PROFILE" \
  "$DMG_SUBMISSION_ID" \
  "$RELEASE_ROOT/notary-dmg-log.json"

xcrun stapler staple -v "$FINAL_DMG"
xcrun stapler validate -v "$FINAL_DMG"
```

DMG는 image 생성 뒤 Developer ID로 별도 서명하고, 그 exact byte의 submission이
`Accepted`인 경우에만 staple한다. DMG log도 별도로 검토한다. 선택한 최종 파일의
checksum을 만들고 즉시 self-check한다.

```sh
export FINAL_ARTIFACT=''
: "${FINAL_ARTIFACT:?Set FINAL_ARTIFACT to FINAL_ZIP or FINAL_DMG}"
cd "$DIST_PATH"
shasum -a 256 "$(basename "$FINAL_ARTIFACT")" > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
cd -
```

checksum은 전송 중 byte 일치를 확인할 뿐 Developer ID signature나 notarization을
대체하지 않는다.

## 7. Clean-user smoke

최종 artifact를 아직 KaosCal을 실행하지 않은 별도 **표준(non-admin) macOS 사용자**에서
검증한다. 최소 지원인 macOS 14와 현재 지원 macOS를 모두 확보하지 못했다면 그 사실을
release blocker 또는 명시적 미검증으로 기록한다.

1. 배포 예정 HTTPS 경로를 Safari로 열어 최종 ZIP/DMG를 다시 다운로드한다. build 폴더의
   app을 복사한 결과로 대체하지 않는다. 실제 다운로드의 quarantine/Gatekeeper 흐름을
   보존한다.
2. 배포 페이지의 SHA-256과 다운로드 파일의 `shasum -a 256` 결과를 비교한다.
3. Finder에서 열고 Gatekeeper 경고를 우회하지 않은 채 KaosCal을 실행한다.
4. 첫 창, app icon, version/build와 Settings의 Local Data 화면을 확인한다.
5. Calendar 권한을 한 번 거부해 복구 안내를 확인하고, System Settings를 통해 해당 exact
   app에 Full Calendar Access를 허용한다. write-only를 full access로 간주하지 않는다.
6. 실제 회사 일정 대신 전용 non-sensitive test calendar에서 Day/Week/Agenda, Event
   Brief와 task 저장·재실행 persistence를 확인한다.
7. 허용된 고유 marker fixture에 한해서 [qa-checklist.md](qa-checklist.md)의 pending live
   gate를 수행한다. 기존 일정은 수정·삭제하지 않는다.
8. plaintext 경고를 읽은 뒤 임시 Event Brief로 export/import와 import/reset 전 recovery
   backup을 확인한다. 복제한 test user에서 DB open을 실패시키고 same-schema backup을
   골라 failed DB/sidecar가 `Recovery`에 보존되는지, 복원 뒤 Event Brief가 열리는지
   확인한다. 사용자의 유일한 실제 DB로 이 fault test를 하지 않는다.
9. app 종료 후 남은 process, crash report, Calendar.app 결과와 test fixture cleanup을
   확인한다.

OS version, hardware architecture, release commit, version/build, artifact SHA-256, Developer
ID leaf, notary submission ID, Gatekeeper 결과, 권한 결과, 실행한 fixture marker와 cleanup을
release record에 남긴다. 계정명, calendar identifier, 일정 본문, credential은 기록하지
않는다.

## 8. 기존 사용자 upgrade smoke

첫 외부 beta 뒤의 모든 release는 clean-user smoke와 별도로 이전 지원 build의 local
container를 가진 표준 사용자에서 upgrade를 검증한다. 첫 beta에는 이전 공개 build가
없음을 기록하고, 이후 비교에 사용할 notarized baseline artifact와 schema를 보존한다.

1. 직전 notarized build를 별도 사용자에서 실행해 비민감 Event Brief/task, change history와
   calendar role을 만들고 재실행 persistence를 확인한다.
2. 현재 DB schema/migration, 이전 app version/build와 수동 backup을 기록하고 앱을
   정상 종료한다. container나 Application Support를 삭제하지 않는다.
3. 배포 예정 artifact로 app을 교체한 뒤 같은 사용자에서 실행한다. 기존 container 접근,
   필요한 migration, Event Brief/task/history/role 보존과 Settings storage path를 확인한다.
4. Calendar 권한과 기존 EventKit 원본이 예상대로 유지되는지 확인하고, upgrade 자체가
   event create/update/delete를 만들지 않았는지 전용 fixture로 점검한다.
5. candidate에서 새 manual backup을 만들고 재실행 persistence를 확인한다. destructive
   import/reset은 별도 복제한 test user/data에서만 수행한다.
6. 이전 binary rollback은 현재 schema/migration을 읽을 수 있다고 별도 증명한 경우만
   시험한다. 호환되지 않으면 rollback 대신 forward-fix가 필요하다고 release record에
   명시한다.

최소 직전 release와 현재 지원하는 가장 오래된 migration baseline을 검증한다. 이 gate를
수행하지 못하면 upgrade 안전을 통과로 기록하지 않고 기존 사용자에게 배포하지 않는다.

## 9. 공개와 rollback

공개 직전 다음을 한 번 더 확인한다.

- CHANGELOG의 `Unreleased`가 실제 날짜가 있는 release 항목으로 바뀌었다.
- checksum, [privacy](../PRIVACY.md), [security/support](../SECURITY.md),
  [known limitations](known-issues.md) 링크와 최소 macOS가 다운로드 페이지에 있다.
- exact artifact가 clean-user smoke를 통과했고 그 byte가 이후 바뀌지 않았다.
- 이전 notarized artifact와 checksum을 별도 보존했다.

문제가 발견되면 다음 순서로 대응한다.

1. 문제 artifact의 다운로드를 즉시 중단하되 파일, checksum, notary log와 source commit은
   조사용으로 보존한다.
2. 사용자에게 KaosCal container, `Backups`, SQLite/WAL/SHM을 삭제하거나 수동 교체하지
   말라고 알린다. 앱이 열리고 DB가 healthy하면 추가 조치 전에 Settings에서 현재 local
   backup을 export한다.
3. 가능하면 같은 또는 더 높은 schema를 읽는 forward-fix build를 새 build number로
   서명·notarize한다.
4. 이전 binary를 다시 배포하는 것은 그 binary가 **현재 사용자의 schema와 migration
   ledger를 읽는다고 별도 검증한 경우에만** 허용한다. Phase 9 import는 exact current
   schema/migration만 받으므로 backup을 이용한 schema downgrade 수단이 아니다.
5. 앱이 DB open/migration 전에 실패하면 Phase 10 bootstrap recovery에서 직접 만든
   same-schema backup만 선택한다. 호환 backup이 없거나 rollback 불완전 오류가 나면 live
   폴더와 `Recovery`를 모두 보존하고 support로 이관하며 reinstall/reset을 복구책으로
   안내하지 않는다.
6. binary rollback은 이미 Calendar.app/Exchange에 반영된 EventKit 변경을 되돌리지
   않는다. session Undo도 재실행 뒤 복구 수단이 아니므로 자동 원복을 약속하지 않는다.

원인, 영향 범위, 중단 시각, 교체 build, DB schema 호환 판정과 사용자 안내를 구현 로그와
release note에 남긴다.

## 10. Release record 최소 항목

- release version/build, source commit/tag, clean worktree 증거
- macOS/Xcode version과 resolved package revision
- 전체 test result bundle과 pass/skip/failure 수
- archive/export 명령, bundle ID, minimum macOS
- Developer ID leaf/Team과 CDHash, runtime·entitlement·XCTest 검증 결과
- notary submission ID/status/log, app 및 DMG stapler 결과
- 최종 artifact 이름, byte size, SHA-256와 보관 위치
- clean-user smoke 환경과 pass/fail/manual-pending 항목
- 기존 사용자 upgrade smoke의 source/target version, schema와 persistence 결과
- rollback 호환 artifact와 schema/migration 판정

Apple의 기준은 [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)을
따른다.
