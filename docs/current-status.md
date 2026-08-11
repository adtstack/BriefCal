# Current Status

> 기준 시각: 2026-08-07, Asia/Seoul
>
> 용도: 현재 진행 상태의 요약. 범위·판정·실행 증거의 원문은 아래 근거 문서를 따른다.

## 요약

- **제품 식별자 기준선:** 제품이 아직 배포되지 않았으므로 공개 이름뿐 아니라 Xcode
  project/scheme/target/module, bundle·test identifier, 앱 실행 파일과 artifact, local DB·backup,
  Keychain·EventKit·Sparkle namespace, build/QA 변수와 URL scheme을 모두 `BriefCal`/
  `briefcal`로 통일했다. 기준은
  [ADR-021](adr/ADR-021-briefcal-pre-release-identity-baseline.md)을 따른다.
- **현재 위치:** v1 기능 개발은 종료·동결했다. v2 T0~T5, calendar visibility/availability,
  saved Calendar Set v9, provider recovery v10과 mini month event dot을 구현했다. 2026-07-20에는
  오른쪽 `Tasks`의 네 provider capability-aware CRUD, Task Center planning v11, provider task와
  Event Brief 연결, calendar time block, Calendar Set filter와 안정화 경로까지 확장했다.
  2026-07-21에는 Google Tasks Desktop OAuth의 dynamic loopback, 승인 scope gate, date-only due와
  명시적 기한 제거 계약을 자동 검증했다. 2026-08-02에는 `COM-003` Full Month MVP와
  상단 calendar view 전환기를 구현했다. 2026-08-03에는 Graph/OAuth 경계, 반복 완료 원자성,
  local data maintenance 격리, 검색·draft·refresh 복구 UX와 자동 품질 gate를 보강했다.
  이어서 EventKit read를 async serial executor 경계로 옮기고 실제 앱을 구동하는 격리 UI
  automation target과 세 가지 핵심 시나리오를 추가했다. 같은 날 ad-hoc+hardened Release가
  Sparkle library validation에서 launch 전에 종료되는 문제를 확인하고, runnable Local Test와
  production-shaped Release 계약을 분리해 실제 launch smoke를 gate로 추가했다.
- **다음 기준:** v1 유지보수 예외는 [v1 동결 결정](v1-freeze.md)을 따르고, 새 동작은 [제품·시스템 스펙](specification.md)의 요구사항 ID와 [v2 실행계획](v2-execution-plan.md)을 먼저 갱신한다.
- **후속 구현 순서:** [상용 기능 로드맵](commercial-feature-roadmap.md)의 C0~C4를 따른다.
  C0는 현재 T0~T5/v10 live·Release 증거다. C1 가운데 Full Month는 구현·자동/offscreen
  검증 완료·live 대기이고, 알림·일정 검색·Quick Add/template·회의 링크 Join은 구현 대기다.
  C2/C3도 이 Mac에서 실행·저장하는 기능만 진행한다. AI, BriefCal
  계정/backend/cloud sync, telemetry, scheduling server와 모바일·웹 companion은
  [ADR-019](adr/ADR-019-local-only-no-ai-no-product-cloud.md)에 따라 C4 영구 제외다.
- **최신 완료 판정 자동 결과:** 제품 식별자 재설정 뒤 329 tests executed, 328 passed,
  1 intentional `ManualEventKitQATests` skip, 0 failures. Result bundle:
  `/private/tmp/BriefCalIdentityTestsFinal.xcresult`. universal Local Test Release
  `/private/tmp/BriefCalIdentityReleaseDerivedData/Build/Products/Release/BriefCal.app`은
  `com.adtstack.briefcal`, 단일 `briefcal://`, arm64/x86_64, strict signature·entitlement,
  XCTest 부재와 실제 launch smoke를 통과했다. Release app executable의 폐기 식별자 검색도
  0건이다.
- **중간 체크포인트:** Apple CRUD 268-test, move/bulk/Undo 271-test와 calendar/planning 집중
  test, Google OAuth/Tasks 집중 test가 각각 통과했으며 최종 판정은 위 322-test 결과를 따른다.
- **새 구현 / live 대기:** 네 provider 직접 CRUD, Apple 목록/account 이동과 Todoist
  project/section 이동, priority capability, local
  planning/checklist/repeat/timer, exact 날짜 filter·저장 view·통합 검색, provider task drag→calendar
  block, Event Brief 연결·상대 기한과 Calendar Set filter, Google Tasks dynamic loopback·scope·
  civil-date due 경계가 전체 자동 suite를 통과했다. 실제 provider·signed app·실창·VoiceOver와
  residue 0 판정은 남아 있다. Google Cloud 준비와 Desktop client ID 주입은 완료했다. 첫 live
  token 교환에서 Desktop client secret 누락을 확인해 Git 밖 `.env`/CI build injection 경로를
  구현했다. 실제 로컬 값이 주입된 clean Debug build와 strict code-sign 검증까지 통과했고 live
  연결 재실행은 대기 중이다. Microsoft To Do는 ID token `oid`와 Graph `/me.id`를 중복
  상호 검증하지 않고, 실제 To Do API access token으로 조회한 opaque Graph `/me.id`를 형식
  변환 없이 tenant와 함께 계정 키의 정본으로 사용한다.
- **Full Month / 자동·offscreen 검증 완료·live 대기:** 연속 주간 scroll, 매월 1일의 3pt 경계와
  locale 월명, 시간+제목, all-day/timed multi-day의 주별 segment, `+N more`와 날짜별 popover, Calendar Set/Enabled filter,
  event→Inspector와 날짜 focus→Day, keyboard/VoiceOver 의미를 구현했다. 상단
  `Day / Week / Month / Agenda` 전환기와 `⌘1`~`⌘5`도 같은 workspace 순서로 연결했다.
  drag 이동·resize, Quarter/Year, 전체 일정 검색, Day Summary와 Quick Add/template은
  이번 범위가 아니다. 560×520의 초기 6주 viewport·고밀도 offscreen bitmap과 전체 회귀는 통과했고,
  실제 창의 keyboard·VoiceOver·appearance와 Exchange fixture 근거는 대기다.
- **자동업데이트 / 발행 대기:** Sparkle 2.9.2 수신기, automatic check/install,
  `Check for Updates…`, signed-feed/pre-extraction 검증과 sandbox helper entitlement를
  구현했다. 유효한 HTTPS feed와 32-byte Ed25519 공개 키가 없으면 updater를 시작하지 않는다.
  실제 Developer ID/notarized archive, HTTPS appcast와 이전-build end-to-end 설치는 아직
  없으며 현재 ad-hoc GitHub prerelease는 update feed가 아니다.
- **외부 베타 판정:** v1에서는 더 이상 추진하지 않는다. final live UI/accessibility/Exchange gate, 실제 bootstrap fault와 Developer ID/notary/license/support 입력은 알려진 제한으로 보존한다.
- **증거 경계:** 최신 Phase 10 Release는 EventKit/Exchange write나 실제 손상 DB recovery를 실행하지 않았다. 실제 Exchange 결과는 아래의 별도 과거 live run에만 귀속한다.

## Phase 0–10

| Phase | 현재 판정 | 확인된 범위 | 남은 gate |
| --- | --- | --- | --- |
| 0 · Repo bootstrap | 완료 | build/test, ad-hoc signing, window 생성 | 없음 |
| 1 · EventKit read-only | 실계정 부분 통과 | full access와 `KAOS-TEST`·`일정`의 Exchange/writable 표시 | 권한 거부·복구 UI, shared read-only, live all-day/recurrence 표시, Calendar.app 변경 반영 |
| 2 · Calendar layout | Day/Week/Agenda·mini month·Full Month 자동/offscreen 완료, live 대기 | Day/Week와 Agenda 주 section의 공통 시간 의미, 선택 주부터 lazy 확장되는 Agenda, timed/all-day 배치, mini month 42일 요약·event dot·접근성 count, 월 경계가 있는 연속 주간 Month·주별 multi-day segment·overflow·상단 view 전환 | `CAL-007`/`UI-005`와 `COM-003` 실창·VoiceOver, Month 고밀도·popover·keyboard, 실제 scroll·선택·inspector와 live all-day/recurrence 배치 |
| 3 · Local context DB | 구현 기준 완료 | v1 DB, repository, identity, 재열기·동시 저장 자동 회귀 | 실제 UI 재실행 유지, identifier churn·detached recurrence |
| 4 · Event Brief / Task Center | 구현·provider 안전성 보강 포함 최신 전체 자동 검증 완료·live 대기 | local notes, Before/During/After, personal/event CRUD, durable provider recovery, 네 provider 직접 CRUD·일괄 완료, Google Cloud External/Testing Desktop client·dynamic loopback·scope/date-only due·revoke local preservation, Git 밖 Desktop credential build injection, Microsoft tenant UUID + opaque Graph account identity, Apple list/account 및 Todoist project/section move, Todoist recent completed projection, local planning v11, exact date/group/saved view/search, Event Brief link·상대 기한, task calendar block·Set filter, 반복 완료 원자성·provider mutation 직렬화 | Google `.env` 실제 값 주입 뒤 실계정 consent·CRUD·revoke/reconnect/residue 0, 실제 4-provider create/update/complete/delete·Apple/Todoist move/Undo·calendar drag/relink·재실행·retry limit·cleanup, 창 focus/menu/검색, 긴 source 문구·VoiceOver |
| 5 · Real event editing | 비반복 live CRUD 부분 통과 | attendee 없는 writable 단일 일정 create→restart/refetch→update→delete와 서버 residue 0 | Calendar.app 시각 round-trip, all-day, floating/zoned time, identifier churn |
| 6 · Recurrence / safe move | 구현·자동·Release checkpoint 완료 | 명시적 scope, impact Confirm, linked safe move, change log, 좁은 session Undo | 지원 범위 내 recurrence scope/future split과 calendar move의 live 검증 |
| 7 · Lifecycle / After Review | 7A–7C 구현, 비반복 linked delete live 통과 | lifecycle, missing/orphan/relink, linked original delete 뒤 local Brief/task 보존 | recurring `thisEvent`, 외부 삭제 지연·one-off exception, crash-window recovery, 남겨 둔 live Brief 정리 |
| 8 · Multi-calendar clarity | role v3·usage v8·saved Set v9 구현과 최종 자동 완료 | local role, Smart Role Filter, 비파괴 duplicate review, calendar별 show/block, 사용자 저장 Set CRUD·순서·exact membership·선택 persistence, offscreen Settings | 실제 계정 grouping·4개 조합·saved Set CRUD/overlap/missing rebind, 긴 문구·고밀도·VoiceOver, shared read-only Exchange |
| 9 · Backup / Settings | 구현·213-test·signed Release·운영 DB 격리·live visual 완료 | healthy current-schema export/import/reset, recovery ZIP, strict archive/schema 검사, 실제 Settings scroll·file panel·typed `RESET` activation | 실제 export 파일 작성·backup 선택 뒤 import/reset mutation, real rollback failure |
| 10 · Paid beta polish | 구현·220-test·ad-hoc Release checkpoint 완료, 외부 beta blocked | onboarding, `⌘R`, empty state, bootstrap-only strict restore/quarantine/rollback, 운영 문서와 license placeholder | final exact Release UI/VoiceOver, 실제 손상 DB recovery, Developer ID/notary/package/clean user, 승인 EULA·support/privacy 연락처와 남은 live Exchange gate |

표의 테스트 수는 해당 시점 checkpoint이며 서로 더하지 않는다. 최신 완료 판정 322-test suite,
review 전 248-test와 237-test calendar-usage checkpoint는 각각 별도 실행 결과다.

## 최신 자동·Release 증거

### 2026-08-03 runnable Local Test 서명·launch checkpoint

- 발견: `/private/tmp/BriefCalQualityHardening-1be4aa5/Build/Products/Release/BriefCal.app`을
  Finder에서 열자 dyld가 `@rpath/Sparkle.framework`를 찾은 뒤 code-signature Team identity
  불일치로 거부했다. crash report의 namespace는 `DYLD`, indicator는 `Library missing`이지만
  실제 파일 부재가 아니라 ad-hoc+hardened runtime library validation 실패였다. strict deep
  `codesign`만으로 실제 동적 로딩 성공을 입증할 수 없다는 품질 공백이다.
- 수정: production-shaped Release는 `BriefCalLocalTestBuild=NO`와 hardened runtime build setting을
  유지하되 Developer ID 없이는 패키징하지 않는다. Finder에서 여는 ad-hoc 산출물은 명시적인
  marker `YES`, `BRIEFCAL_LOCAL_TEST_BUILD` compiler condition과 hardened runtime 비활성화를 함께
  사용한다. 실제 배포는 같은 Developer ID Team으로 app/nested code를 서명하고 marker `NO`와
  hardened runtime을 유지해야 한다.
- 자동 gate: `scripts/build_local_test_app.sh`와 `verify_local_test_app.sh`가 universal build,
  strict deep signature, app sandbox·Calendar·Reminders entitlement, host architecture,
  `get-task-allow`·XCTest 부재를 확인한다. 이어 Debug/Local Test에만 포함된 in-memory fixture로
  앱을 3초 실행해 Sparkle dyld load와 bootstrap 생존을 확인한다. CI zip과 tag DMG도 같은
  launch smoke를 통과해야 한다.
- 실행 결과: universal app
  `/private/tmp/BriefCalRunnableLocalTest/Build/Products/Release/BriefCal.app`은 marker `YES`,
  ad-hoc signature, hardened runtime 부재를 확인했다. 직접 app 2회, ZIP 압축 해제본과 읽기 전용
  DMG mount 내부 app이 각각 launch smoke를 통과했고 새 BriefCal crash report는 없었다. 검증 DMG는
  `/private/tmp/BriefCalSigningFix-local.dmg`, SHA-256은
  `704d13f15a995cb8fc3a19d7702e74e109c1feb64377ef20f1b57564ca7e8d47`이다. 일반 실행에는
  `--ui-testing`이 없어 실제 Calendar/local DB 경로로 시작한다.
- 회귀: 전체 **322 executed / 321 passed / 1 intentional `ManualEventKitQATests` skip /
  0 failures**, result bundle `/private/tmp/BriefCalSigningFixUnit.xcresult`. app line coverage
  **53.61% (29,698/55,395)**, 정적 분석, production-shaped universal Release compile과 UI
  `build-for-testing`이 통과했다.
- 경계: Local Test는 Developer ID/notarized 배포물이나 updater source가 아니다. 실제 XCUITest
  세 시나리오 실행은 현재 host Developer Tools authorization 대기 상태와 분리한다.

### 2026-08-03 UI 자동화·EventKit 비동기 경계 checkpoint

- unit 결과: 전체 **322 executed / 321 passed / 1 intentional `ManualEventKitQATests` skip /
  0 failures**. 후속 signing fix까지 포함한 최신 result bundle은
  `/private/tmp/BriefCalSigningFixUnit.xcresult`다.
  `BriefCal.app` line coverage는 **53.61% (29,698/55,395)**로 50% floor를 통과했다.
- EventKit read 경계: `listCalendars`, `fetchEvents`, `lookupEvent`를 async 계약으로 바꾸고
  long-lived `EKEventStore`의 모든 read를 전용 serial executor에서 실행한다. raw `EKEvent`와
  `EKCalendar`는 executor 안에서 `Sendable` 값 snapshot으로 변환한 뒤에만 AppState로 돌아온다.
  write도 같은 executor에 직렬화해 read/write store 접근 순서를 보존했다. strict concurrency
  complete build는 통과했지만 다른 provider 파일의 기존 warning까지 해결한 것으로 보지 않는다.
- UI automation: `BriefCalUITests` target과 Debug-only `--ui-testing` bootstrap을 추가했다.
  in-memory DB와 고정 calendar fixture로 Day/Week/Month/Agenda/Tasks 이동, Agenda event→Inspector/
  Event Brief→new editor, transient refresh 실패 뒤 stale data+warning/Retry 보존의 세 시나리오를
  작성했다. 실제 Calendar, Keychain, provider 계정과 운영 DB는 사용하지 않는다.
- 실행 경계: UI target의 ad-hoc signed `build-for-testing`은 통과했다. 현재 로컬 host는
  Developer Mode가 disabled라 UI test runner가 테스트 본문 전에 초기화되지 않았으므로 세
  시나리오를 pass로 계산하지 않는다. 시스템 전체 설정은 명시적 사용자 승인 없이 바꾸지 않았다.
  CI/Release는 unit suite와 UI automation을 분리하고 두 `.xcresult`를 모두 보존한다.
- build gate: `xcodebuild analyze`, production-shaped Release compile과 Local Test Release의
  bundle ID·macOS 14 minimum·XCTest 미포함 검증이 통과했다. 실제 launch 증거는 위 signing
  checkpoint가 대체한다.
- 남은 비배포 품질 경계: 승인된 host에서 UI 세 시나리오 실제 실행, 실창 VoiceOver/keyboard,
  전면 localization, 대형 AppState/View 책임 분리, EventKit 외 provider의 남은 strict concurrency
  warning과 실제 provider fixture 검증이다.

### 2026-08-03 안전·원자성·품질 보강 checkpoint

- 결과: 전체 **319 executed / 318 passed / 1 intentional `ManualEventKitQATests` skip /
  0 failures**. Result bundle은 `/private/tmp/BriefCalQualityFinal2.xcresult`다.
  `BriefCal.app` line coverage는 **53.63% (29,559/55,121)**로 50% floor를 통과했고
  `xcodebuild analyze`, workflow YAML 구문 검사와 `git diff --check`도 통과했다.
- provider/OAuth 안전성: Microsoft Graph continuation을 exact HTTPS origin과 `/v1.0` 경로로
  제한하고 pagination 상한·반복 cursor 차단을 추가했다. Microsoft To Do deep link도 공식
  web origin만 연다. OAuth는 duplicate parameter, cross-origin redirect, non-loopback listener,
  oversized/incomplete/absolute-form callback을 거부하며 잘못된 callback 한 번이 정상 callback을
  선점하지 못한다.
- 데이터 원자성·격리: 반복 task 완료, timer actual, 다음 occurrence와 planning/checklist 복사를
  단일 DB transaction으로 묶었다. export/import/reset은 새 provider 작업을 막고 진행 중인
  refresh를 취소·대기한 뒤 수행한다. backup은 migration 집합뿐 아니라 orphan planning/checklist와
  안전하지 않은 reference URL도 거부한다.
- 복구 UX: calendar 검색 결과가 exact occurrence 날짜와 event를 열고 숨겨진 event만 임시로
  reveal한다. provider source가 사라져도 dirty editor를 보존하고, transient calendar refresh
  실패는 기존 화면을 유지한 채 warning/Retry를 제공한다. provider 연결 해제에는 영향 범위를
  설명하는 확인 단계를 추가했다.
- 품질 자동화: coverage 50% floor, 정적 분석과 최소 지원 macOS 호환성 job을 CI/Release gate에
  추가했다. Todoist 동일 task mutation은 순서대로 직렬화하고 제품 UI의 혼재된 한국어 문구를
  현재 기준 언어인 영어로 정리했다.
- 이 checkpoint에서 남았던 UI automation target과 EventKit read async/off-main 경계는 위 후속
  checkpoint에서 구현했다. 실창 VoiceOver/keyboard, 전면 localization, 대형 AppState/View
  책임 분리와 실제 provider 계정 검증은 계속 별도다.

### 2026-08-02 Full Month MVP 구현 checkpoint

- 결과: **구현·자동/offscreen 검증 완료 / live 대기**. 전체 **312 executed / 311 passed /
  1 intentional `ManualEventKitQATests` skip / 0 failures**이며 result bundle은
  `/private/tmp/BriefCalMonthDerived/Logs/Test/Test-BriefCal-2026.08.02_19-55-49-+0900.xcresult`다.
- 구현 범위: 4~6주 Month grid, 시간+제목, all-day/timed multi-day 주별 segment,
  자정 배타 종료, deterministic lane, `+N more`/popover, Calendar Set/Enabled,
  event→Inspector, 날짜 focus→Day, 상단 view picker, `⌘1`~`⌘5`, keyboard/VoiceOver semantics.
- 제외 범위: drag 이동·resize, Quarter/Year, 전체 일정 검색, Day Summary,
  Quick Add/template.
- offscreen: Sunday-first 6주와 multi-day continuation, 밀집일 `+3 more`를 560×520 bitmap으로
  렌더해 셀·막대·overflow 잘림이 없음을 확인했다.
- live 대기: 실제 Exchange fixture, 좁은 창·고밀도 overflow, 빠른 월 이동 중 loading/error,
  keyboard focus, VoiceOver, light/dark와 Increase Contrast.

### 2026-07-25 signed automatic updater 구현·Release gate

- 결과: **297 executed / 296 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle:
  `/private/tmp/BriefCalAutomaticUpdatesFinalTests.xcresult`
- Sparkle `2.9.2` exact revision `6276ba2b404829d139c45ff98427cf90e2efc59b`를 pin하고,
  HTTPS feed와 32-byte base64 공개 키 구성의 valid/missing/insecure 계약 3건을 추가했다.
  구성 없는 build는 앱을 정상 실행하되 updater와 update menu action을 비활성화한다.
- synthetic public configuration을 주입한 universal ad-hoc Release:
  `/private/tmp/BriefCalAutomaticUpdatesRelease/Build/Products/Release/BriefCal.app`, CDHash
  `28dabda20f68e7894b09db2e3957922c4fda867d`.
- `x86_64`/`arm64`, hardened runtime, strict deep code-sign과 Sparkle framework,
  Autoupdate, Updater.app, Downloader.xpc, Installer.xpc 포함을 확인했다. app entitlement의
  mach service는 `com.adtstack.briefcal-spks`와 `com.adtstack.briefcal-spki`이고 XCTest는 없다.
  Info.plist의 automatic check/install, signed-feed와 pre-extraction verification도 `true`이고
  Sparkle system profiling은 plist/runtime에서 비활성화했다.
- 이 artifact의 feed와 공개 키는 치환 검증용 synthetic 값이며 실제 update를 발행하지
  않았다. Developer ID/notarization, signed HTTPS appcast, 변조/오프라인 실패와 직전
  notarized build의 자동 설치·재실행·local DB 보존은 live/manual pending이다.
- 이 checkpoint의 strict signature audit에는 실제 Sparkle launch가 없었다. 2026-08-03 확인한
  ad-hoc+hardened runtime library-validation 실패 때문에 이 artifact를 runnable local-test
  근거로 사용하지 않으며, 위 Local Test launch checkpoint가 현재 경로를 대체한다.
- 현재 GitHub origin은 private이라 인증 없는 Sparkle feed로 직접 사용할 수 없다. token을
  앱에 포함하지 않고 별도 정적 HTTPS endpoint를 정하는 운영 입력이 남아 있다.

### 2026-07-24 Microsoft Graph identity 정본화·universal Release gate

- 결과: **293 executed / 292 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle:
  `/tmp/BriefCalMicrosoftOpaqueCleanFull/Logs/Test/Test-BriefCal-2026.07.24_09-51-42-+0900.xcresult`
- Microsoft ID token `oid`와 Graph `/me.id`의 앱 내부 상호 검증을 제거했다. token의 UUID
  `tid`와 실제 To Do access token으로 조회한 opaque Graph `/me.id`를 계정 키에 사용한다.
  Graph ID는 UUID로 가정하거나 대소문자를 변환하지 않는다. 서로 다른 token `oid`와 opaque
  Graph ID를 받은 정상 연결, 빈 Graph ID의 credential 미저장 회귀가 통과했다.
- universal ad-hoc Release:
  `/tmp/BriefCalMicrosoftOpaqueRelease-20260724/Build/Products/Release/BriefCal.app`, CDHash
  `6d8f5c18877b47c656f4558a8a87b1ba2ae064c7`.
- `x86_64`/`arm64`, hardened runtime, strict code-sign, app sandbox·Calendar·Reminders·파일 선택·
  network client/server entitlement, XCTest 미포함과 기존 inconsistent/invalid Graph identity
  오류 문자열 미포함을 확인했다. Developer ID 서명·notarization을 거친 공개 배포물은 아니다.

### 2026-07-23 Microsoft identity 정규화·최종 universal Release gate

- 결과: **293 executed / 292 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle:
  `/tmp/BriefCalFinalGate/Logs/Test/Test-BriefCal-2026.07.23_17-51-14-+0900.xcresult`
- Microsoft ID token `oid`와 Graph `/me.id`를 문자열 표기가 아닌 UUID 값으로 비교한다. 같은
  GUID의 대소문자 차이는 허용하고 실제 다른 GUID는 credential 저장 전에 거부하는 회귀가
  통과했다.
- universal ad-hoc Release:
  `/tmp/BriefCalFinalUniversalRelease-20260723/Build/Products/Release/BriefCal.app`, CDHash
  `9d5300b0b2f6195dafeb109231d5448017a00493`.
- `x86_64`/`arm64`, hardened runtime, strict code-sign, app sandbox·Calendar·Reminders·파일 선택·
  network client/server entitlement, 실제 로컬 OAuth build setting 주입과 XCTest 비포함을
  확인했다. Developer ID 서명·notarization을 거친 공개 배포물은 아니다.

### 2026-07-23 Google Desktop credential build injection 자동 gate

- 결과: **292 executed / 291 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalGoogleSecretFullTests.xcresult`
- 범위: Git-ignored 루트 `.env`의 optional xcconfig 주입, Google token/refresh request의 조건부
  form-encoded `client_secret`, dynamic redirect 교체 뒤 credential 보존, 값 없는 build의
  `Not configured` 경계를 포함한다.
- 자동 suite 전 가짜 build-setting 검증 값은 즉시 제거했으며 secret 원문은 어느 결과에도
  기록하지 않았다.
- 이후 Git-ignored 실제 로컬 `.env`로 clean Debug build를 생성하고 app 안의 client ID,
  loopback redirect와 credential의 비어 있지 않음을 원문 출력 없이 확인했다. strict code-sign도
  통과했다. app: `/tmp/BriefCalGoogleLiveSecretBuild-20260723/Build/Products/Debug/BriefCal.app`

### 2026-07-23 Google Cloud 구성·pre-push 자동 gate

- 결과: **292 executed / 291 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalGooglePrePushFinal.xcresult`
- 실계정 테스트용 local ad-hoc Debug app:
  `/tmp/BriefCalGoogleLiveTestApp/Build/Products/Debug/BriefCal.app`
- 별도 app build와 strict code-sign 검증이 통과했고, app `Info.plist`에서 공개 Google Desktop
  client ID와 `http://127.0.0.1` redirect base 확장을 확인했다. client secret/token 패턴은
  저장소에서 검출되지 않았다.
- 남은 live gate: 실제 consent, 양방향 CRUD·conflict·재실행/refresh, 권한 철회·재연결과
  양쪽 residue 0.

### 2026-07-21 Google Tasks 실계정 활성화 전 자동 gate

- 결과: **292 executed / 291 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle:
  `/tmp/BriefCalGooglePlanBaseline/Logs/Test/Test-BriefCal-2026.07.21_18-29-25-+0900.xcresult`
- 범위: Google Desktop OAuth의 임의 loopback 포트와 authorization/token redirect 일치,
  callback state/path·거부·timeout·중복 완료, 필수 `openid`/Tasks scope 확인 전 credential
  미저장, UTC/KST/America/New_York civil-date due, 명시적 due `null`, list/task pagination,
  완료/미완료, ETag conflict, 401 단일 refresh와 403/404/429 오류, 철회·만료된 refresh token의
  credential 제거와 reconnect-required 전환, account/binding metadata와 local task 보존을
  포함한다. 현재
  Tasks drawer와 Microsoft OAuth 사용자 변경을 포함한 전체 회귀도 함께 통과했다.
- artifact: local ad-hoc Debug
  `/tmp/BriefCalGooglePlanBaseline/Build/Products/Debug/BriefCal.app`
- Google Cloud 준비 완료: Tasks API 활성화, External/Testing audience, test user 등록,
  Desktop OAuth client 생성과 공개 `BRIEFCAL_GOOGLE_TASKS_CLIENT_ID` 주입을 완료했다.
- 남은 live gate: 실제 consent, CRUD·권한 철회·재연결과 residue 0은 아직 실행하지 않았다.
  Google Calendar 직접 API는 추가하지 않았다.

### 2026-07-20 Tasks 통합 관리·계획·Calendar 결합 최종 자동 결과

- 결과: **280 executed / 279 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle:
  `/tmp/BriefCalUnifiedTasksCompleteBuild/Logs/Test/Test-BriefCal-2026.07.20_14-16-19-+0900.xcresult`
- artifact: local ad-hoc Debug
  `/tmp/BriefCalUnifiedTasksCompleteBuild/Build/Products/Debug/BriefCal.app`
- 범위: Apple Reminders·Google Tasks·Todoist·Microsoft To Do 공통 조회/생성/완료/편집/삭제,
  Apple 목록·계정 이동, Todoist project/section 이동과 일괄 이동·최근 90일 완료 projection,
  priority/Microsoft reminder capability와 version-aware Undo, v11 local planning,
  Today/Upcoming/Overdue/No Date/Completed, grouping·saved view·통합 검색, 기존 provider task의
  Event Brief 연결, 상대 기한, drag→calendar block, 연결 일정 이동과 Calendar Set filter를
  포함한다. v10 Event Brief durable pending/retry/local-only와 기존 Calendar 회귀도 함께 통과했다.
- 한계: unsigned fake/local 중심 자동 결과다. 실제 iCloud/On My Mac, Google, Todoist와
  Microsoft 계정의 CRUD·충돌·권한·deep link, Apple/Todoist move/Undo, calendar drag 부분 성공,
  residue 0, signed app keyboard·VoiceOver는 수동 gate다.

### 2026-07-20 Tasks Apple Reminders 직접 관리 자동 결과

- 결과: **271 executed / 270 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalTasksInteractionBuild/Logs/Test/Test-BriefCal-2026.07.20_12-32-46-+0900.xcresult`
- 범위: explicit remote task ID/version, Apple-only exact account/list/task write route, 생성,
  완료·미완료, 제목·전체 notes·기한 수정/제거, 목록·계정 간 이동, 삭제, 단일·일괄
  완료/이동의 version-aware session Undo, conflict, read-only, 권한 철회, metadata 실패,
  외부 삭제, 이동 binding 보존, 삭제 Undo의 새 remote ID 재연결, 기존 provider 재연결과
  300/360pt Tasks offscreen 회귀를 포함한다.
- artifact: unsigned Debug `/tmp/BriefCalTasksInteractionBuild/Build/Products/Debug/BriefCal.app`
- 한계: 실제 iCloud/On My Mac Reminders와 signed app, TCC 철회·복구, 외부 동시 수정,
  move/Undo cleanup, keyboard·VoiceOver 실창 검증은 남아 있다. Microsoft mutation과 task의
  Calendar 연결·시간 배치는 이 checkpoint 뒤 위 통합 결과에서 구현·자동 검증됐다.

### 2026-07-17 Task Provider P1/P2 코드 체크포인트

- remote/local projection hash와 version을 함께 비교해 remote-only 반영, local-only push,
  양쪽 변경 conflict를 나누고 remote 삭제는 자동 재생성하지 않는 missing으로 유지한다.
- create/update/delete 전에 v10 pending row를 저장하고 명시적 재시도를 최대 3회로 제한한다.
  task별 local-only 선택, destination 변경 전 기존 unbound task 고정, provider/account/list/task
  exact 후보 선택과 atomic relink를 추가했다.
- Microsoft task 설명은 원문을 SQLite/backup에 넣지 않고 프로세스 첫 full delta에서 다시
  채운다. Google의 date-only due는 timed due hash에서 제외하되 remote due 변경은 cache와
  비교해 적용·충돌 판정한다.
- 검증: Debug app `build`와 `build-for-testing` 컴파일, `git diff --check` 성공.
  사용자 요청에 따라 테스트 실행과 실제 계정 조작은 하지 않았다.

### 2026-07-16 Tasks list 필터·가독성 최종 결과

- 결과: **257 executed / 256 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalTasksFilters-Final-R2-20260716.xcresult`
- 범위: provider·account·list 복합 식별자, 빈 list를 포함한 Apple Reminders/Microsoft To Do
  선택지, 같은 provider/account 경계의 raw ID 충돌 방지, list·Open/Completed/All·제목/
  설명 검색·due/title 정렬 조합, 재실행 preference 복원, 일시적 metadata fallback, 삭제된
  선택 list의 All fallback과 300×600/360×700 offscreen 가독성 회귀를 포함한다.
- 한계: unsigned Debug·fake provider·offscreen 결과다. 실제 Apple/Microsoft 계정의 menu,
  긴 현지화 문구, keyboard·VoiceOver와 light/dark 실창 판정은 남아 있다.

### 2026-07-16 Apple Reminders Tasks 직접 연결 최종 결과

- 결과: **254 executed / 253 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalRemindersConnection-Final-20260716.xcresult`
- 범위: 오른쪽 `Tasks`의 전체 높이, 첫 진입 시 Apple Reminders 권한 요청, 거부 시
  System Settings 복구, 연결 상태의 상시 표시와 권한 승인 후 실제 provider list/task
  projection을 포함한 전체 회귀다. 이름 `Tasks`는 유지했다.
- 한계: 권한 요청과 list/task projection은 fake provider 자동 검증이다. 실제 macOS TCC
  prompt 수락·거부·복구와 iCloud/On My Mac Reminders 실계정 표시는 수동 gate다.

### 2026-07-15 Task Provider recovery·mini month event dot 최종 결과

- 결과: **253 executed / 252 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalProviderMiniMonth-Final-R3-20260715.xcresult`
- 범위: Task Center provider/account/list projection, missing/conflict/disconnected 상태 전환과
  명시적 remote/local recovery, mini month 별도 42-civil-day snapshot, 본문 snapshot 보존,
  DST·자정·timed multi-day·all-day 배타 종료, global Enabled·선택 Set·blocking 독립,
  loading/unavailable/failure 접근성 의미와 기존 전체 회귀를 포함한다.
- 한계: fake/local/unsigned Debug 중심이다. 실제 provider 계정·충돌·cleanup, 다른 remote
  직접 relink·durable per-task unlink, event-dot 실창·VoiceOver와 signed Release는 대기다.

### 2026-07-15 saved Calendar Set review 수정 후 최종 전체 결과

- 결과: **250 executed / 249 passed / 1 intentional manual-only skip / 0 failures**
- result bundle: `/tmp/BriefCalCalendarSets-Final-20260715.xcresult`
- 범위: saved Set 데이터·AppState·Settings/offscreen 회귀와 review의 normal visibility 조건부
  reveal, post-write focus reveal, authoritative missing-state guard를 포함한 최종 작업 트리
  전체 suite다.
- 한계: 자동/fake/local/offscreen 결과는 실제 Exchange calendar identifier churn,
  Settings/Sidebar 실창·keyboard·VoiceOver, 새 signed Release와 운영 DB 불변을 대신하지 않는다.

### 2026-07-15 saved Calendar Set review 수정 후 집중 결과

- build 성공, focused suites **73 tests / 0 failures**
- result bundle:
  `/tmp/BriefCalCalendarSets/Logs/Test/Test-BriefCal-2026.07.15_18-53-22-+0900.xcresult`
- 범위에는 새 UI와 post-write focus 회귀가 포함된다. 이후 위 250-test 최종 전체 결과로
  승격됐다.

### 2026-07-15 saved Calendar Set v9 자동 결과(review 수정 전)

- 결과: **248 executed / 247 succeeded / 1 intentional manual-only skip / 0 failed**,
  action status `succeeded`
- result bundle:
  `/tmp/BriefCalCalendarSetsDataTests/Logs/Test/Test-BriefCal-2026.07.15_18-36-07-+0900.xcresult`
- 집중 데이터 결과: ContextStore/LocalDataBackupService **84 executed / 84 succeeded /
  0 skipped / 0 failed**, action status `succeeded`; result bundle
  `/tmp/BriefCalCalendarSetsDataTests/Logs/Test/Test-BriefCal-2026.07.15_18-34-47-+0900.xcresult`
- 범위: `v9_saved_calendar_sets`, Set CRUD·정렬·exact membership·missing 보존/명시적
  rebind·selection persistence/삭제 fallback, global Enabled·blocking 독립, overlapping/
  mixed-role/empty Set, duplicate temporary reveal, backup/reset과 Settings offscreen 회귀를
  포함한다.
- 집계 근거: `xcresulttool`의 metrics/testsRef에서 `testStatus`를 직접 집계했다.
- 후속 변경: 이 실행 뒤 normal visibility 조건부 reveal, write focus reveal, missing 판정의
  authoritative-state guard가 수정됐다. 최종 판정은 위 250-test bundle을 따른다.
- 한계: unsigned Debug와 fake/local store 및 offscreen UI 중심 결과다. 실제 Exchange
  calendar identifier churn, Settings/Sidebar 실창·keyboard·VoiceOver, 새 Release signing과
  운영 DB 불변은 검증하지 않았다.

### 2026-07-15 calendar usage 자동 결과(saved Set v9 이전)

- 결과: **237 executed / 236 passed / 1 intentional manual-only skip / 0 failures / 0 unexpected**, `TEST SUCCEEDED`
- result bundle: `/tmp/BriefCalCalendarUsageFullTests-20260715-1445.xcresult`
- 범위: 기존 전체 회귀, v2 task provider/reference migration·contract, calendar visibility와
  availability blocking의 독립 설정·sparse persistence·free/cancelled/declined 제외,
  Settings offscreen bitmap과 backup/reset 회귀를 포함한다.
- 제외: `v9_saved_calendar_sets`, saved Set CRUD·membership·selection persistence와 해당 UI는
  이 result bundle 이후 구현이므로 이 수치로 통과 판정하지 않는다.
- 한계: unsigned Debug와 fake/local store 중심 결과다. 실제 Exchange/provider fixture,
  Settings·Sidebar 실창/VoiceOver, Release signing과 운영 DB 불변을 새로 검증하지 않았다.
- 관찰: `testCalendarUsageSettingsFitsAndProducesOffscreenBitmap`은 pass했지만 종료 시 임시
  `calendar-settings.sqlite`가 열린 file descriptor보다 먼저 unlink됐다는 libsqlite 경고를
  한 번 출력했다. production DB 경로는 사용하지 않았으며 test fixture cleanup 순서는 후속
  점검으로 남긴다.
- 문서: 현행 동작과 인수 기준은 [제품·시스템 스펙](specification.md)에 요구사항 ID로
  정리했다. 이 checkpoint는 아래 과거 exact Release/live 증거를 최신 build로 승격하지 않는다.
- offscreen test resource lifetime 정리 뒤
  `/tmp/BriefCalCalendarUsageUIFinal-20260715-1450.xcresult`에서 해당 UI test 1/1을
  경고 없이 재통과했다. production code는 위 전체 suite와 같다.

### Phase 10 자동 결과

- 결과: **220 executed / 219 passed / 1 intentional manual-only skip / 0 failures / 0 unexpected**
- result bundle: `/private/tmp/BriefCalPhase10Tests.xcresult`
- 범위: 기존 전체 회귀에 bootstrap invalid-archive no-touch, DB+WAL/SHM/journal 격리와
  restore, replacement 검증 실패 뒤 원본 전체 rollback, onboarding/recovery offscreen
  bitmap을 추가했다.
- 한계: offscreen은 final live window/VoiceOver를 대신하지 않고, filesystem rollback 자체
  실패·power-loss와 실제 sandbox 손상 DB file-panel recovery는 별도 gate다.

### Phase 10 Release

- artifact: `/private/tmp/BriefCalPhase10Release/Build/Products/Release/BriefCal.app`
- CDHash: `4d7c1b5ad6dde65666f101cae00bdcb9d5b878ed`
- 확인: ad-hoc signing, hardened runtime, strict codesign, sandbox·Calendar·user-selected
  read/write entitlement, version `0.1.0` build `1`, `get-task-allow`·XCTest 부재
- 데이터 안전: 전체 test와 Release smoke 전후 direct/sandbox 운영 DB의 mtime·size·SHA-256,
  integrity와 WAL/SHM/journal 부재가 이전 checkpoint와 동일
- live 경계: 중간 Release 실창에서 onboarding button clipping과 명시적 Continue 없는
  completion 저장을 발견해 수정했다. 최종 CDHash build는 기존 Xcode dev instance의 같은
  bundle-ID window 소유 때문에 재관찰하지 못했으므로 final live pass로 올리지 않는다.
- 배포 한계: Developer ID/notarization/stapling을 통과한 외부 배포 artifact가 아니다.

### Phase 9 자동 결과

- 결과: **213 executed / 212 passed / 1 intentional manual-only skip / 0 failures / 0 unexpected**
- result bundle: `/private/tmp/BriefCalPhase9FinalTests-20260712-1535.xcresult`
- 문서·release review 재실행: `/private/tmp/BriefCalReviewTests.xcresult`, 같은 213 executed /
  212 passed / 1 intentional skip / 0 failures / 0 unexpected, `TEST SUCCEEDED`
- 범위: strict backup archive/schema/destination, import/reset recovery, rollback-failure quarantine, Settings offscreen render, fake provider의 EventKit write 0회
- 한계: fake provider와 test DB 결과는 실제 Calendar.app·Exchange 또는 실제 Settings panel 상호작용을 대신하지 않는다.

### Phase 9 Release

- artifact: `/private/tmp/BriefCalPhase9FinalRelease-20260712-1535/Build/Products/Release/BriefCal.app`
- CDHash: `4f6eb184110ca317a440c5d640cf0670e4c42753`
- 확인: ad-hoc signing, hardened runtime, strict codesign, sandbox·Calendar·user-selected read/write entitlement, `get-task-allow`·XCTest 부재
- runtime: exact Release가 1512×949 visible window를 만들고 종료됨
- 데이터 안전: 전체 test와 Release 기동 전후 direct/sandbox 운영 DB의 mtime·size·SHA-256, integrity/FK, WAL/SHM/journal 부재가 불변
- 배포 한계: Developer ID 서명·notarization·stapling을 통과한 외부 배포 artifact는 아니다.

## 분리 보존하는 live 증거

- **2026-07-11 · `20260711-1626-B7D2`:** full calendar access, 두 writable Exchange calendar, attendee 없는 비반복 fixture의 create→앱 재실행/refetch→update→delete와 서버 residue 0 통과
- **2026-07-12 · `20260712-025027-KST`:** 비반복 linked 원본의 final delete 1회, Calendar.app·Outlook 원본 부재, local Brief·Notes·Before/During/After task 보존 통과
- **2026-07-12 · `20260712-1616-KST`:** Phase 9 exact Release의 620×652 Settings 전체 scroll, 880×448 Export/Import panel, privacy/storage copy, `RESET` 입력 뒤 Delete 활성화 통과. 모든 작업은 취소했고 파일 작성·import·reset은 실행하지 않았으며 운영 DB와 process는 불변

이 결과는 각 run의 exact signed Release에만 귀속한다. 더 최신 Phase 9 build가 같은 live 경로를 재실행했다는 뜻이 아니다. recurring `thisEvent` fixture는 session lock으로 실행하지 못했으므로 통과나 실패로 계산하지 않는다.

## 남은 live/manual gate

1. 권한 거부→System Settings 복구와 shared read-only Exchange 설명
2. Day/Week/Month/Agenda·mini month·Inspector·Task Center의 실제 고밀도, Month overflow
   popover, keyboard, scroll, VoiceOver
3. Calendar usage·saved Set Settings/Sidebar의 show/block 네 조합, saved Set CRUD·순서·겹침·혼합 role,
   exact membership·missing 보존/명시적 Replace, 재실행·backup/reset, account bulk action,
   free/busy/tentative/canceled/declined, 고밀도·keyboard·VoiceOver
4. Calendar.app 시각 CRUD, all-day, floating/zoned time, 반복 scope/future split, linked calendar move
5. 외부 삭제·identifier churn·detached/one-off recurrence recovery와 Phase 7C crash window
6. Apple Reminders, Google Tasks, Todoist, Microsoft To Do의 실제 계정 create/update/complete/delete/relink와 cleanup
7. 실제 export 파일 작성, backup 선택 뒤 import/reset mutation과 core restore/rollback fault
8. final Phase 10 exact Release onboarding/recovery UI, keyboard/VoiceOver와 복제 test-user의 실제 failed-bootstrap recovery
9. clean user/account beta QA, Developer ID signing, notarization, stapling, DMG/ZIP, 승인 EULA·support/privacy 연락처와 설치·철회 절차
10. Sparkle private key backup, signed HTTPS appcast/archive 발행과 직전 notarized build의
    자동업데이트 발견·설치·재실행·offline/변조 거부·local DB 보존

상세 절차와 판정 기준은 [QA checklist](qa-checklist.md), fixture별 실계정 상태는 [Exchange compatibility](exchange-compatibility.md)를 따른다.
Phase 10의 외부 입력과 미검증 항목은 [Phase 10 Blockers](phase10-blockers.md)에 계속 기록한다.

## 근거 우선순위

실행 결과를 판정할 때는 다음 순서를 사용한다.

1. exact signed artifact와 run ID가 있는 live 결과: EventKit, BriefCal UI, Calendar.app/서버, local DB, cleanup을 각각 기록한 증거
2. exact Release audit: codesign·entitlement·runtime·운영 DB 불변 증거
3. result bundle이 있는 자동 테스트: fake provider/test DB 범위
4. offscreen·fixture render
5. 계획·설계 문구만 있고 실행 기록이 없는 항목

자동 테스트는 live pass로 승격하지 않고, offscreen render는 실제 panel·keyboard·VoiceOver pass로 승격하지 않는다. 최신 checkpoint도 다시 실행하지 않은 종류의 과거 증거를 대체하지 않는다.

문서별 권한은 다음과 같다.

- 제품·안전 결정: 최신 accepted [ADR](adr/README.md)
- v1 제공·제외 범위: [V1 Scope](v1-scope.md)
- phase 인수 기준: [Phase Plan](phase-plan.md)과 [QA checklist](qa-checklist.md)
- 실행 결과: [Implementation Log](implementation-log.md)과 [Exchange compatibility](exchange-compatibility.md)
- 현재 요약: 이 문서. 위 원문에서 파생하며 원문과 충돌할 때 더 강하고 최신인 원문 증거를 우선한다.

## 업데이트 규칙

- phase 판정이나 최신 suite/Release가 바뀌면 같은 변경에서 이 문서도 갱신한다.
- `pass`, `partial`, `manual pending`, `blocked`, `not tested`를 구분하고 실행하지 않은 항목을 실패나 통과로 바꾸지 않는다.
- live pass에는 날짜, run ID, exact artifact/CDHash, fixture, 관찰 지점과 cleanup 결과를 남긴다.
- intentional skip은 pass 수에 포함하지 않고 이유와 대체되지 않는 gate를 적는다.
- `/private/tmp` artifact는 임시 증거다. release candidate 판정에는 재현 가능한 새 artifact와 결과를 다시 만든다.
- 계정·이메일·raw event/calendar ID, 실제 notes/task 본문과 credential은 상태 문서에 기록하지 않는다.
