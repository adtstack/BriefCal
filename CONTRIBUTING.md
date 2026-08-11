# Contributing to BriefCal

BriefCal은 macOS Calendar/EventKit의 원본 일정과 로컬 Event Brief 데이터를 엄격히
분리한다. 변경은 이 안전 경계를 유지하고, 구현·자동 검증·수동 증거를 서로 대체하지
않아야 한다.

## 개발 환경

- macOS 14 이상
- 전체 Xcode. 현재 checkpoint 재현 환경은 Xcode 26.6 / Build 17F113이다. 다른 Xcode
  version은 별도 검증 없이 같은 결과를 보장하지 않는다.
- repository root의 `BriefCal.xcodeproj`와 shared `BriefCal` scheme
- SwiftPM pin을 기록한
  `BriefCal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- 실제 EventKit 검증이 필요할 때만 macOS Internet Accounts에 구성된 전용 test
  calendar. Exchange credential, password, MFA, OAuth token은 앱·환경변수·저장소에
  넣지 않는다.

환경을 확인한다.

```sh
xcode-select -p
xcodebuild -version
xcodebuild -project BriefCal.xcodeproj -scheme BriefCal -list
```

처음 clone한 환경에서 package가 local cache에 없으면 pinned revision만 resolve한다.

```sh
xcodebuild \
  -resolvePackageDependencies \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates
```

일반 build/test에서 `Package.resolved`를 변경하거나 package update를 허용하지 않는다.
의도적인 dependency 변경은 source, version, resolved revision, license를 함께 review하고
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 같은 변경에서 갱신한다.

## Build

일상적인 compile 확인은 서명 없이 실행한다.

```sh
xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BriefCalDerivedData \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  build
```

배포가 아닌 로컬 entitlement/runtime 검증에는 ad-hoc Release를 사용한다.

```sh
xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BriefCalAdHocRelease \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

codesign --verify --deep --strict --verbose=2 \
  /private/tmp/BriefCalAdHocRelease/Build/Products/Release/BriefCal.app
codesign -d --verbose=4 \
  /private/tmp/BriefCalAdHocRelease/Build/Products/Release/BriefCal.app
codesign -d --entitlements - \
  /private/tmp/BriefCalAdHocRelease/Build/Products/Release/BriefCal.app
```

ad-hoc app은 private/public beta 배포물이 아니다. Developer ID와 notarization 절차는
[release-runbook.md](docs/release-runbook.md)를 따른다.

## 자동 테스트

전체 suite를 기본으로 실행한다.

저장소의 versioned CI는 최신 검증 러너에서 전체 자동 test, 50% app-target line coverage
하한, Xcode static analyzer와 unsigned Release build를 수행한다. 여기서 만든 동일한 Local
Test ZIP은 최소 지원 macOS 14 runner에서 signature·payload·실제 launch smoke를 검증한다.
변경 제출자는 아래 local 명령도 실행해 빠르게 피드백을 확인한다. CI는 pinned SwiftPM,
production DB 격리와 manual EventKit opt-in 경계를 유지하며, CI 성공을 live Exchange나
clean-user 배포 통과로 해석하지 않는다.

```sh
xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BriefCalDerivedData \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  test
```

최신 baseline 수치는 [Current Status](docs/current-status.md)를 따른다. test가
추가·삭제되면 숫자 자체보다 모든 비수동 test의 성공과 예상하지 않은 skip/failure 0개를
기준으로 삼고, 새 결과를 [implementation-log.md](docs/implementation-log.md)와 Current
Status에 함께 기록한다.

특정 test만 실행해 개발 시간을 줄일 수 있지만 최종 변경에는 전체 suite가 필요하다.

```sh
xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BriefCalFocusedTests \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:BriefCalTests/LocalDataBackupServiceTests \
  test
```

## EventKit 수동 opt-in

`ManualEventKitQATests/testManualExchangeGate`는 기본 suite에서 provider를 만들기 전에
skip되는 **읽기 전용 preflight**다. 이 test는 권한을 요청하거나 event를 쓰지 않는다.
EventKit 수동 검증은 자동 test 통과와 별개이며 명시적으로 opt-in한다.

1. [developer-setup.md](docs/developer-setup.md)의 현재 허용된 전용 test calendar와
   [qa-checklist.md](docs/qa-checklist.md)의 fixture/cleanup 규칙을 확인한다.
2. 같은 Derived Data path에 최종 test host를 `build-for-testing`으로 먼저 만든다.
   이후 `test-without-building`을 사용해야 권한을 승인한 app과 test가 실행할 app의
   signature/CDHash가 달라지지 않는다.

```sh
export EVENTKIT_DERIVED_DATA=/private/tmp/BriefCalEventKitQA

xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$EVENTKIT_DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build-for-testing

export EVENTKIT_TEST_HOST="$EVENTKIT_DERIVED_DATA/Build/Products/Debug/BriefCal.app"
codesign --verify --deep --strict --verbose=2 "$EVENTKIT_TEST_HOST"
codesign -d --verbose=4 "$EVENTKIT_TEST_HOST"
open "$EVENTKIT_TEST_HOST"
```

3. exact host에서 `Allow Full Calendar Access`를 누르고 macOS prompt를 사용자가 직접
   승인한다. 앱에 `Full calendar access`가 표시되는지 확인한 뒤 앱을 종료한다.
4. 실제 test calendar 이름과 non-sensitive run ID/output path를 설정하고 preflight만
   실행한다.

```sh
export BRIEFCAL_EVENTKIT_QA_MODE=inspect
export BRIEFCAL_EVENTKIT_SOURCE=''
export BRIEFCAL_EVENTKIT_DESTINATION=''
export BRIEFCAL_EVENTKIT_QA_RUN_ID=''
export BRIEFCAL_EVENTKIT_QA_OUTPUT=''

: "${BRIEFCAL_EVENTKIT_SOURCE:?Set a dedicated source calendar name}"
: "${BRIEFCAL_EVENTKIT_DESTINATION:?Set a distinct dedicated destination calendar name}"
: "${BRIEFCAL_EVENTKIT_QA_RUN_ID:?Set a unique non-sensitive run ID}"
: "${BRIEFCAL_EVENTKIT_QA_OUTPUT:?Set an output JSON path under /private/tmp}"

xcodebuild \
  -project BriefCal.xcodeproj \
  -scheme BriefCal \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$EVENTKIT_DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  -only-testing:BriefCalTests/ManualEventKitQATests/testManualExchangeGate \
  test-without-building
```

report에는 calendar title과 결과가 들어갈 수 있으므로 검토용 임시 파일로만 다루고
민감한 account/source/event identifier나 본문을 commit하지 않는다. Calendar.app에서
보는 live create/update/delete, all-day, recurrence, move, shared read-only와 Settings
panel 검증은 이 preflight가 수행하지 않으며 QA checklist의 별도 gate를 따른다. 허용된
고유 marker fixture 외 기존 event는 수정·삭제하지 않는다.

## 변경 원칙

- EventKit event가 원본 일정의 source of truth이고 Event Brief/task는 local SQLite에
  남는다는 소유권 경계를 유지한다.
- 참석자/초대, read-only, weak/ambiguous identity와 지원하지 않는 recurrence 범위는
  provider write 전에 차단한다. 지원하는 all-day·floating/IANA time zone과 기본
  recurrence 변경은 validation, explicit scope와 impact confirmation 경계를 유지한다.
- 실행 중 SQLite 파일이나 WAL/SHM을 filesystem copy/replace하지 않는다. backup/import/
  reset 계약은 [backup-restore.md](docs/backup-restore.md)와 ADR-015를 따른다.
- unrelated dirty worktree를 덮어쓰거나 되돌리지 않는다. generated output과 credential을
  commit하지 않는다.
- 실제 계정 검증은 test 전용 calendar와 고유 marker로만 수행하고 exact cleanup을
  확인한다.

## 코드 스타일과 commit 범위

현재 repository-wide SwiftFormat/SwiftLint configuration은 없다. 기존 Swift 파일의
4-space indentation, 명시적인 domain type과 작은 mutation 경계를 따르고, 기능 변경과
무관한 대량 reformat은 섞지 않는다. compiler warning을 새로 만들지 않으며 formatter를
도입하거나 규칙을 바꾸면 설정·적용 범위·CI 여부를 별도 변경으로 기록한다.

commit은 한 가지 동작·안전 경계 또는 문서 목적에 집중한다. 사용자 변경을 되돌리거나
unrelated dirty file을 stage하지 않고, generated artifact·credential·production DB·backup은
commit하지 않는다.

## 문서와 변경 기록

[ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 따라 사용자가 보는 동작,
지원 범위, 데이터/backup 형식, QA 기준, architecture 또는 dependency가 바뀌면 같은
변경에서 문서를 갱신한다.

- 제품 범위: `docs/v1-scope.md`, 관련 ADR
- EventKit/Exchange 결과: `docs/exchange-compatibility.md`, QA, implementation log
- schema/data model: `docs/data-model.md`, migration test, 관련 ADR
- 실제 구현·검증: `docs/implementation-log.md`, `docs/phase-plan.md`,
  `docs/qa-checklist.md`
- 현재 phase·최신 suite/Release·열린 gate: `docs/current-status.md`
- 배포·version: `CHANGELOG.md`, `docs/distribution.md`, release runbook
- dependency/license: `Package.resolved`, `THIRD_PARTY_NOTICES.md`

검증하지 않은 동작은 `pass`나 지원 완료로 쓰지 않는다. 자동 fake-provider 결과,
ad-hoc build, EventKit live run, Exchange server fetch, Calendar.app 시각 결과와 clean-user
배포 결과를 각각 구분하고 artifact path/CDHash/run ID에 귀속한다.

## Troubleshooting

### `xcodebuild`가 Command Line Tools만 사용한다

`xcode-select -p`와 `xcodebuild -version`을 확인한다. 전체 Xcode의 Developer directory를
선택하되 설치 경로를 추측하지 않는다. 일회성 확인은 실제 설치 경로로 다음처럼 한다.

```sh
DEVELOPER_DIR='/path/to/Xcode.app/Contents/Developer' xcodebuild -version
```

### SwiftPM resolve/build가 예상과 다르다

`Package.resolved` diff를 먼저 확인한다. package version을 자동으로 올리거나 resolved
file을 삭제하지 않는다. network/cache가 필요한 최초 resolve와 dependency update를
구분하고, update가 의도된 경우 license notice까지 review한다.

### test result bundle이 이미 존재한다고 실패한다

`-resultBundlePath`는 새 경로를 사용해야 한다. 기존 `.xcresult`를 덮어써서 과거 증거를
잃지 말고 timestamp가 다른 `/private/tmp` 경로를 사용한다.

### Calendar 권한이 계속 denied/notDetermined다

unsigned build로는 수동 EventKit gate를 수행하지 않는다. 검증할 exact signed app을 먼저
실행하고 사용자가 직접 macOS prompt를 승인한다. 이전 artifact의 TCC 상태를 새 artifact의
증거로 재사용하지 않고, write-only를 full access로 간주하지 않는다. account password나
MFA를 환경변수로 넣어 해결하지 않는다.

### 기본 suite에서 ManualEventKitQATests가 skip된다

정상이다. `BRIEFCAL_EVENTKIT_QA_MODE=inspect` 또는 source/destination 이름이 없으면
의도적으로 skip한다. run ID와 output path는 test가 임시 기본값을 만들 수 있지만,
수동 증거를 재현할 때는 위처럼 명시한다. 일반 회귀를 통과시키기 위해 이 변수를 전역
shell profile이나 scheme에 영구 저장하지 않는다.

### Local Data import/reset이 거부된다

검사를 우회하지 않는다. 현재 app identifier/schema/migration과 정확히 같은 신뢰 가능한
BriefCal backup만 import할 수 있다. app이 DB open 전에 실패하면 기존 DB와 sidecar를
보존한다. 앱 시작 전에 DB open이 실패한 경우에는 Settings의 bootstrap recovery에서 검증된
동일-schema backup을 선택한다. live writer가 열린 뒤에는 이 복구 경로를 사용할 수 없다.

## 변경 제출 전 확인

- pinned dependency로 Debug build와 전체 test가 성공했다.
- 예상하지 않은 skip/failure가 없다.
- 사용자 동작과 안전 경계에 해당하는 test를 추가하거나 갱신했다.
- 필요한 manual gate는 pass/pending/blocked와 artifact/run 근거를 구분해 기록했다.
- 관련 ADR·scope·QA·phase·implementation log와 CHANGELOG가 함께 갱신됐다.
- secret, raw account/calendar/event identifier, production DB, backup ZIP, `.xcresult`,
  Derived Data와 build artifact가 diff에 없다.
- dependency 변경이면 exact resolved revision과 license/bundling gate를 다시 확인했다.
