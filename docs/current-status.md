# Current Status

> 기준 시각: 2026-07-16, Asia/Seoul
>
> 용도: 현재 진행 상태의 요약. 범위·판정·실행 증거의 원문은 아래 근거 문서를 따른다.

## 요약

- **현재 위치:** v1 기능 개발은 종료·동결했다. v2 T0/T1, OAuth task provider T2/T3, T4의 EventKit 유지 결정, T5 reference-only 계층과 동결 후 calendar visibility/availability blocking, saved Calendar Set v9, Task Center provider recovery, mini month event dot, Tasks의 Apple Reminders 직접 연결과 list/source 필터·가독성 개선까지 저장소와 UI를 확장했다. 최종 257-test suite는 통과했고 실제 Exchange/provider·실창·VoiceOver gate는 별도 대기 중이다. 자동 테스트만으로 beta ready를 선언하지 않는다.
- **다음 기준:** v1 유지보수 예외는 [v1 동결 결정](v1-freeze.md)을 따르고, 새 동작은 [제품·시스템 스펙](specification.md)의 요구사항 ID와 [v2 실행계획](v2-execution-plan.md)을 먼저 갱신한다.
- **최신 완료 자동 결과:** 257 tests executed, 256 passed, 1 intentional `ManualEventKitQATests` skip, 0 failures
- **중간 체크포인트:** 이전 254-test와 Tasks 300/360pt offscreen·filter focused test도 통과했으며 최종 판정은 257-test 결과를 따른다.
- **새 구현 / live 대기:** Task Center의 provider/account/list 상태·명시적 missing/conflict/disconnected 복구, mini month 일정 존재 표시 `CAL-007`/`UI-005`, Tasks 안의 Apple Reminders 권한 요청·거부 복구·연결 상태, Apple/Microsoft list 선택·상태·검색·정렬 필터와 읽기 계층을 구현했다. 자동 회귀는 통과했지만 실제 provider·실창·VoiceOver 판정은 남아 있다.
- **외부 베타 판정:** v1에서는 더 이상 추진하지 않는다. final live UI/accessibility/Exchange gate, 실제 bootstrap fault와 Developer ID/notary/license/support 입력은 알려진 제한으로 보존한다.
- **증거 경계:** 최신 Phase 10 Release는 EventKit/Exchange write나 실제 손상 DB recovery를 실행하지 않았다. 실제 Exchange 결과는 아래의 별도 과거 live run에만 귀속한다.

## Phase 0–10

| Phase | 현재 판정 | 확인된 범위 | 남은 gate |
| --- | --- | --- | --- |
| 0 · Repo bootstrap | 완료 | build/test, ad-hoc signing, window 생성 | 없음 |
| 1 · EventKit read-only | 실계정 부분 통과 | full access와 `KAOS-TEST`·`일정`의 Exchange/writable 표시 | 권한 거부·복구 UI, shared read-only, live all-day/recurrence 표시, Calendar.app 변경 반영 |
| 2 · Calendar layout | 구현·자동·offscreen 검증 완료, event dot live 대기 | Day/Week/Agenda 공통 범위, timed/all-day 배치, mini month 42일 요약·event dot·접근성 count | `CAL-007`/`UI-005` 실창·VoiceOver, 실제 고밀도 scroll·선택·inspector, live all-day/recurrence 배치 |
| 3 · Local context DB | 구현 기준 완료 | v1 DB, repository, identity, 재열기·동시 저장 자동 회귀 | 실제 UI 재실행 유지, identifier churn·detached recurrence |
| 4 · Event Brief / Task Center | 구현·자동·fixture 시각 검증 완료 | local notes, Before/During/After, personal/event task CRUD, provider source/status와 명시적 recovery, Tasks 전체 높이·Apple Reminders 직접 권한 요청/복구, Apple/Microsoft list·상태·검색·정렬 필터와 300/360pt offscreen | 실제 provider·창의 focus·menu·검색·삭제·재실행, 긴 source 문구·VoiceOver, 다른 remote 직접 relink와 durable per-task unlink |
| 5 · Real event editing | 비반복 live CRUD 부분 통과 | attendee 없는 writable 단일 일정 create→restart/refetch→update→delete와 서버 residue 0 | Calendar.app 시각 round-trip, all-day, floating/zoned time, identifier churn |
| 6 · Recurrence / safe move | 구현·자동·Release checkpoint 완료 | 명시적 scope, impact Confirm, linked safe move, change log, 좁은 session Undo | 지원 범위 내 recurrence scope/future split과 calendar move의 live 검증 |
| 7 · Lifecycle / After Review | 7A–7C 구현, 비반복 linked delete live 통과 | lifecycle, missing/orphan/relink, linked original delete 뒤 local Brief/task 보존 | recurring `thisEvent`, 외부 삭제 지연·one-off exception, crash-window recovery, 남겨 둔 live Brief 정리 |
| 8 · Multi-calendar clarity | role v3·usage v8·saved Set v9 구현과 최종 자동 완료 | local role, Smart Role Filter, 비파괴 duplicate review, calendar별 show/block, 사용자 저장 Set CRUD·순서·exact membership·선택 persistence, offscreen Settings | 실제 계정 grouping·4개 조합·saved Set CRUD/overlap/missing rebind, 긴 문구·고밀도·VoiceOver, shared read-only Exchange |
| 9 · Backup / Settings | 구현·213-test·signed Release·운영 DB 격리·live visual 완료 | healthy current-schema export/import/reset, recovery ZIP, strict archive/schema 검사, 실제 Settings scroll·file panel·typed `RESET` activation | 실제 export 파일 작성·backup 선택 뒤 import/reset mutation, real rollback failure |
| 10 · Paid beta polish | 구현·220-test·ad-hoc Release checkpoint 완료, 외부 beta blocked | onboarding, `⌘R`, empty state, bootstrap-only strict restore/quarantine/rollback, 운영 문서와 license placeholder | final exact Release UI/VoiceOver, 실제 손상 DB recovery, Developer ID/notary/package/clean user, 승인 EULA·support/privacy 연락처와 남은 live Exchange gate |

표의 테스트 수는 해당 시점 checkpoint이며 서로 더하지 않는다. 최신 257-test suite,
review 전 248-test와 237-test calendar-usage checkpoint는 각각 별도 실행 결과다.

## 최신 자동·Release 증거

### 2026-07-16 Tasks list 필터·가독성 최종 결과

- 결과: **257 executed / 256 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/KaosCalTasksFilters-Final-R2-20260716.xcresult`
- 범위: provider·account·list 복합 식별자, 빈 list를 포함한 Apple Reminders/Microsoft To Do
  선택지, 같은 provider/account 경계의 raw ID 충돌 방지, list·Open/Completed/All·제목/
  설명 검색·due/title 정렬 조합, 재실행 preference 복원, 일시적 metadata fallback, 삭제된
  선택 list의 All fallback과 300×600/360×700 offscreen 가독성 회귀를 포함한다.
- 한계: unsigned Debug·fake provider·offscreen 결과다. 실제 Apple/Microsoft 계정의 menu,
  긴 현지화 문구, keyboard·VoiceOver와 light/dark 실창 판정은 남아 있다.

### 2026-07-16 Apple Reminders Tasks 직접 연결 최종 결과

- 결과: **254 executed / 253 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/KaosCalRemindersConnection-Final-20260716.xcresult`
- 범위: 오른쪽 `Tasks`의 전체 높이, 첫 진입 시 Apple Reminders 권한 요청, 거부 시
  System Settings 복구, 연결 상태의 상시 표시와 권한 승인 후 실제 provider list/task
  projection을 포함한 전체 회귀다. 이름 `Tasks`는 유지했다.
- 한계: 권한 요청과 list/task projection은 fake provider 자동 검증이다. 실제 macOS TCC
  prompt 수락·거부·복구와 iCloud/On My Mac Reminders 실계정 표시는 수동 gate다.

### 2026-07-15 Task Provider recovery·mini month event dot 최종 결과

- 결과: **253 executed / 252 passed / 1 intentional manual-only skip / 0 failures**,
  `TEST SUCCEEDED`
- result bundle: `/tmp/KaosCalProviderMiniMonth-Final-R3-20260715.xcresult`
- 범위: Task Center provider/account/list projection, missing/conflict/disconnected 상태 전환과
  명시적 remote/local recovery, mini month 별도 42-civil-day snapshot, 본문 snapshot 보존,
  DST·자정·timed multi-day·all-day 배타 종료, global Enabled·선택 Set·blocking 독립,
  loading/unavailable/failure 접근성 의미와 기존 전체 회귀를 포함한다.
- 한계: fake/local/unsigned Debug 중심이다. 실제 provider 계정·충돌·cleanup, 다른 remote
  직접 relink·durable per-task unlink, event-dot 실창·VoiceOver와 signed Release는 대기다.

### 2026-07-15 saved Calendar Set review 수정 후 최종 전체 결과

- 결과: **250 executed / 249 passed / 1 intentional manual-only skip / 0 failures**
- result bundle: `/tmp/KaosCalCalendarSets-Final-20260715.xcresult`
- 범위: saved Set 데이터·AppState·Settings/offscreen 회귀와 review의 normal visibility 조건부
  reveal, post-write focus reveal, authoritative missing-state guard를 포함한 최종 작업 트리
  전체 suite다.
- 한계: 자동/fake/local/offscreen 결과는 실제 Exchange calendar identifier churn,
  Settings/Sidebar 실창·keyboard·VoiceOver, 새 signed Release와 운영 DB 불변을 대신하지 않는다.

### 2026-07-15 saved Calendar Set review 수정 후 집중 결과

- build 성공, focused suites **73 tests / 0 failures**
- result bundle:
  `/tmp/KaosCalCalendarSets/Logs/Test/Test-KaosCal-2026.07.15_18-53-22-+0900.xcresult`
- 범위에는 새 UI와 post-write focus 회귀가 포함된다. 이후 위 250-test 최종 전체 결과로
  승격됐다.

### 2026-07-15 saved Calendar Set v9 자동 결과(review 수정 전)

- 결과: **248 executed / 247 succeeded / 1 intentional manual-only skip / 0 failed**,
  action status `succeeded`
- result bundle:
  `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-36-07-+0900.xcresult`
- 집중 데이터 결과: ContextStore/LocalDataBackupService **84 executed / 84 succeeded /
  0 skipped / 0 failed**, action status `succeeded`; result bundle
  `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-34-47-+0900.xcresult`
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
- result bundle: `/tmp/KaosCalCalendarUsageFullTests-20260715-1445.xcresult`
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
  `/tmp/KaosCalCalendarUsageUIFinal-20260715-1450.xcresult`에서 해당 UI test 1/1을
  경고 없이 재통과했다. production code는 위 전체 suite와 같다.

### Phase 10 자동 결과

- 결과: **220 executed / 219 passed / 1 intentional manual-only skip / 0 failures / 0 unexpected**
- result bundle: `/private/tmp/KaosCalPhase10Tests.xcresult`
- 범위: 기존 전체 회귀에 bootstrap invalid-archive no-touch, DB+WAL/SHM/journal 격리와
  restore, replacement 검증 실패 뒤 원본 전체 rollback, onboarding/recovery offscreen
  bitmap을 추가했다.
- 한계: offscreen은 final live window/VoiceOver를 대신하지 않고, filesystem rollback 자체
  실패·power-loss와 실제 sandbox 손상 DB file-panel recovery는 별도 gate다.

### Phase 10 Release

- artifact: `/private/tmp/KaosCalPhase10Release/Build/Products/Release/KaosCal.app`
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
- result bundle: `/private/tmp/KaosCalPhase9FinalTests-20260712-1535.xcresult`
- 문서·release review 재실행: `/private/tmp/KaosCalReviewTests.xcresult`, 같은 213 executed /
  212 passed / 1 intentional skip / 0 failures / 0 unexpected, `TEST SUCCEEDED`
- 범위: strict backup archive/schema/destination, import/reset recovery, rollback-failure quarantine, Settings offscreen render, fake provider의 EventKit write 0회
- 한계: fake provider와 test DB 결과는 실제 Calendar.app·Exchange 또는 실제 Settings panel 상호작용을 대신하지 않는다.

### Phase 9 Release

- artifact: `/private/tmp/KaosCalPhase9FinalRelease-20260712-1535/Build/Products/Release/KaosCal.app`
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
2. Day/Week/Agenda·mini month·Inspector·Task Center의 실제 고밀도, keyboard, scroll, VoiceOver
3. Calendar usage·saved Set Settings/Sidebar의 show/block 네 조합, saved Set CRUD·순서·겹침·혼합 role,
   exact membership·missing 보존/명시적 Replace, 재실행·backup/reset, account bulk action,
   free/busy/tentative/canceled/declined, 고밀도·keyboard·VoiceOver
4. Calendar.app 시각 CRUD, all-day, floating/zoned time, 반복 scope/future split, linked calendar move
5. 외부 삭제·identifier churn·detached/one-off recurrence recovery와 Phase 7C crash window
6. Apple Reminders, Google Tasks, Todoist, Microsoft To Do의 실제 계정 create/update/complete/delete/relink와 cleanup
7. 실제 export 파일 작성, backup 선택 뒤 import/reset mutation과 core restore/rollback fault
8. final Phase 10 exact Release onboarding/recovery UI, keyboard/VoiceOver와 복제 test-user의 실제 failed-bootstrap recovery
9. clean user/account beta QA, Developer ID signing, notarization, stapling, DMG/ZIP, 승인 EULA·support/privacy 연락처와 설치·철회 절차

상세 절차와 판정 기준은 [QA checklist](qa-checklist.md), fixture별 실계정 상태는 [Exchange compatibility](exchange-compatibility.md)를 따른다.
Phase 10의 외부 입력과 미검증 항목은 [Phase 10 Blockers](phase10-blockers.md)에 계속 기록한다.

## 근거 우선순위

실행 결과를 판정할 때는 다음 순서를 사용한다.

1. exact signed artifact와 run ID가 있는 live 결과: EventKit, KaosCal UI, Calendar.app/서버, local DB, cleanup을 각각 기록한 증거
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
