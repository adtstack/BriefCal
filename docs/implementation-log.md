# Implementation Log

이 문서는 실제로 한 작업과 검증 결과를 시간순으로 남긴다. 계획만 적지 않고, 명령·테스트·수동 검증의 성공 또는 실패를 모두 기록한다.

## 기록 규칙

- 코드 또는 사용자에게 보이는 동작을 바꾸면 같은 변경에서 항목을 추가한다.
- 각 항목에는 날짜, 관련 ADR, 변경 파일, 검증, 남은 위험을 적는다.
- 검증하지 못한 내용은 `미검증`으로 명시한다. 추측을 통과로 기록하지 않는다.

## 2026-07-13 — v1 기능 동결 및 v2 단계 문서화

- 관련 결정: [v1 동결 결정](v1-freeze.md), [v2 실행계획](v2-execution-plan.md)
- 변경:
  - v1 기능 개발 종료선과 유지보수 예외를 `docs/v1-freeze.md`에 기록했다.
  - 통합 캘린더·Task 로드맵을 T0~T5 실행계획과 연결했다.
  - Provider abstraction, Apple Reminders, Google Tasks/Todoist, Microsoft To Do,
    직접 Calendar API 조사, Notes/reference의 단계별 세부문서를 추가했다.
  - `current-status.md`, `phase-plan.md`, 루트 README와 문서 인덱스에 v1 동결과 v2 기준을
    반영했다.
- 검증:
  - 새 문서 간 상대 링크와 Markdown 형식은 별도 문서 점검에서 확인한다.
  - 코드는 변경하지 않았으며, v1 테스트·Release 증거를 재실행하거나 승격하지 않았다.
- 남은 결정:
  - 실제 v1 기준선 commit/tag 보존은 동결 운영 절차에서 수행한다.
  - T0 schema·destination 변경 정책·stable account key·capability 공통 타입은 T0 착수
    전에 확정한다.

## 2026-07-10 — 문서 기준선 복원 및 v1 결정 정리

- 관련 ADR: ADR-001, ADR-002, ADR-003, ADR-004, ADR-005
- 변경: 원격 `origin/main`의 기존 문서 기준선을 로컬 `main`에 복원하고, v1 범위·Exchange 호환성·개발 준비·ADR 구조를 추가했다.
- 보존: 기존 `.gitignore`의 사용자 변경은 유지했다.
- 검증:
  - `git status --short --branch`에서 `main...origin/main`과 기존 `.gitignore` 변경을 확인했다.
  - `docs/` 10개 초기 문서가 작업 폴더에 복원된 것을 확인했다.
  - `git diff --check`가 통과해 문서 변경에 whitespace 오류가 없음을 확인했다.
  - Xcode 앱이 설치되어 있지 않아 앱 빌드·EventKit 실계정 검증은 **미검증**이다.
- 남은 위험: Exchange Online의 실제 권한·공유·반복·시간대 동작, EventKit ID 재연결, 배포 서명.

## 2026-07-10 — 개발 및 Exchange 테스트 환경 준비 확인

- 관련 ADR: ADR-001
- 확인:
  - Xcode 26.6 / Build 17F113이 설치되어 있다.
  - 사용자가 macOS 인터넷 계정에서 Exchange 계정 로그인과 Calendar 동기화를 완료했다.
  - 수정 가능한 테스트 calendar 이름은 `KAOS-TEST`다.
  - 사용자는 앱의 full calendar access 요청을 허용할 예정이다.
  - Exchange Online 또는 온프레미스 여부는 **미확인**으로 유지한다.
- 보안: 비밀번호, MFA 코드, OAuth token, client secret은 필요하지 않으며 저장하지 않는다.
- 결과: Phase 0 앱 bootstrap을 시작할 수 있다.
- 남은 위험: read-only 공유 calendar 미준비, Exchange backend 종류 미확인.

## 2026-07-10 — Phase 0 네이티브 앱 bootstrap 완료

- 관련 ADR: ADR-002, ADR-005, ADR-006
- 변경 파일:
  - `KaosCal.xcodeproj`와 shared `KaosCal` scheme
  - `KaosCal/App`, `Features/CalendarShell`, `DesignSystem`, `Resources`
  - `KaosCalTests/AppStateTests.swift`
  - Xcode/Swift build artifact용 `.gitignore`
- 동작:
  - BusyCal의 정보 밀도만 참고한 독자적인 3-pane shell
  - Day/Week/Agenda/Tasks navigation과 `Command-1`~`Command-4`
  - Day/Week all-day lane 및 시간 grid placeholder
  - Agenda, Task Center, Event Brief empty state
  - Phase 1 전에는 permission을 요청하거나 `KAOS-TEST`를 runtime에 하드코딩하지 않음
- 빌드 기준:
  - Xcode 26.6 / Swift compiler 6.3.3 / Swift language mode 5
  - macOS 14.0+, bundle identifier `com.adtstack.kaoscal`
  - App Sandbox + Calendar entitlement + full-access usage description
- 검증:
  - `plutil -lint` project/Info.plist/entitlement: pass
  - unsigned Debug build: pass
  - XCTest: 5 tests, 0 failures
  - ad-hoc signed Debug build: pass
  - `codesign --verify --deep --strict`: pass
  - sandbox/calendar/get-task-allow entitlement 확인: pass
  - built Info.plist full-access usage description 확인: pass
  - 실행 프로세스와 `KaosCal` window 생성 확인: pass
- 제약:
  - 데스크톱 접근성 검증용 `orca` CLI가 설치되어 있지 않아 pixel-level/AX-tree 검사는 수행하지 못했다.
  - Phase 0 shell은 실제 EventKit 데이터가 아닌 disconnected/empty state만 표시한다.
- 결과: Phase 0 완료. 다음 단계는 Phase 1 EventKit full access와 Exchange calendar/event read-only 조회다.

## 2026-07-10 — Phase 1 EventKit read-only 구현 및 자동 검증 완료

- 관련 ADR: ADR-001, ADR-003, ADR-004, ADR-005, ADR-006
- 변경 파일:
  - `KaosCal/CalendarKit`: authorization/source/event 값 모델, provider protocol, long-lived `EventKitProvider`, 날짜 범위 표시
  - `KaosCal/App/AppState.swift`: 권한 흐름, -30/+90일 조회, store change 재조회, 선택 event state
  - `KaosCal/Features/CalendarShell/CalendarShellView.swift`: full access 설명·요청·복구, calendar sidebar, read-only/Exchange 표시, Agenda와 inspector
  - `KaosCalTests`: fake provider 기반 권한·오류·알림·날짜 의미 회귀 테스트
  - architecture, EventKit 결정, phase, QA, Exchange compatibility 문서
- 동작:
  - macOS 14+ `requestFullAccessToEvents`만 사용하고 password/MFA/token을 받지 않는다.
  - full access 전에는 event fetch를 하지 않는다.
  - 권한 거부·제한·write-only는 System Settings 복구 화면으로 보낸다.
  - 앱이 다시 active가 되면 System Settings에서 바뀐 권한을 재확인한다.
  - 권한 철회 시 calendar, event, 선택 state를 즉시 비운다.
  - `EKEventStoreChanged` 연속 알림은 250ms 병합한 뒤 현재 범위를 재조회한다.
  - UI에는 `EKEvent`를 보관하지 않고 값 snapshot만 전달한다.
  - 종일 일정의 배타 종료 날짜와 자정을 넘는 시간 일정의 날짜 범위를 사람이 읽는 형태로 표시한다.
  - Xcode Preview는 실제 EventKit에 접근하지 않는다.
- 자동 검증:
  - project/Info.plist/entitlement `plutil -lint`: pass
  - `git diff --check`: pass
  - unsigned Debug XCTest: **15 tests, 0 failures**
  - unsigned Release build: pass
  - ad-hoc signed Debug build: pass
  - `codesign --verify --deep --strict`: pass
  - signed entitlement에서 app sandbox, Calendar access, get-task-allow 확인: pass
  - built Info.plist의 `NSCalendarsFullAccessUsageDescription` 확인: pass
- 실행 검증:
  - signed `KaosCal.app` 실행과 프로세스 생성: pass
  - 데스크톱 접근성 도구 `orca`가 설치되어 있지 않고 `osascript` 접근성 권한도 없어 UI tree 자동 검사는 수행하지 못했다.
  - 사용자의 macOS full access 승인과 실제 `KAOS-TEST`/Exchange/writable 노출은 **진행 중**이다.
- 보안:
  - runtime에 계정 자격 증명이나 `KAOS-TEST` 이름을 하드코딩하지 않았다.
  - 실제 event 제목·내용·계정 식별자를 테스트 로그와 문서에 기록하지 않는다.
- 결과: 코드·자동·서명 검증 pass, Phase 1 최종 판정은 실계정 수동 검증 대기.
- 계획 변경: 3-pane shell은 Phase 0, 실제 Agenda 목록은 Phase 1에 구현되었다. Phase 2는 Day/Week 실제 이벤트 배치·겹침과 세 화면 일관성에 집중하도록 phase plan을 갱신했다.
- 이월: 공유 read-only Exchange calendar가 없어 실계정 read-only 판정은 `blocked`다. Day/Week 구현은 계속하고 Phase 8 호환성 게이트 전에 해소한다.
- 남은 위험: Exchange backend 종류 unknown, 실제 TCC/System Settings UI 미검증, KC-E1/KC-E2/KC-E4와 외부 변경 알림 실계정 검증 미완료.

## 2026-07-10 — Phase 2 Day/Week/Agenda 실제 배치 구현 및 자동 검증 완료

- 관련 ADR: ADR-003, ADR-004, ADR-005, ADR-007
- 변경 파일:
  - `KaosCal/CalendarKit/CalendarEventLayout.swift`: Foundation-only timed/all-day layout, 날짜 분할, span/row, visual interval, overlap column
  - `CalendarModels`, `EventKitProvider`, `CalendarEventDateFormatting`: 시간 의미, UI occurrence identity, calendar color snapshot, all-day raw end 정규화, 명시적 calendar/time zone formatting
  - `AppState`: Day 1일·Week/Agenda 7일 visible period, 화면 밖 확장 조회, stale 조회 취소, 선택 정리
  - `CalendarTimelineView`, `CalendarShellView`, `KaosCalTheme`: 실제 24시간 Day/Week, 고정 header/all-day lane, current-time, event card, 고밀도 scroll, 캘린더별 rail, 접근성 identifier
  - `CalendarEventLayoutTests`와 기존 fixture: 레이아웃·시간 의미·범위 조회 회귀 테스트
  - ADR-007, architecture, EventKit, design, phase, QA, compatibility, data model, scope/setup 문서
- 동작:
  - Day/Week/Agenda는 같은 반개구간 visible interval과 정렬된 `visibleEvents`를 사용한다.
  - 시간 일정은 현지 자정에서 나누고 24시간 wall-clock 축에 배치한다. fall-back의 같은 현지 시각은 별도 column으로 표시한다.
  - 짧은 일정은 배치에만 최소 24분을 사용하며 자정 근처 visual start 이동도 같은 collision interval로 계산한다.
  - 종일·다일 일정은 배타 종료로 span을 만들고, 고밀도 lane은 35%·240pt에서 내부 세로 scroll한다.
  - EventKit이 all-day end를 `23:59:59`로 정규화하는 로컬 SDK 동작을 재현하고, 자정 raw end와 함께 provider 경계에서 배타 종료 자정으로 통일했다.
  - all-day/floating components에 원 calendar identifier를 보존해 non-Gregorian 표시 달력에서도 날짜가 이동하지 않게 했다.
  - 초기 오늘 -30/+90일을 벗어나면 visible interval 주변을 다시 읽고, 빠른 왕복 navigation의 pending far-range 조회는 취소한다.
  - actual EventKit calendar color snapshot을 sidebar, Agenda, timed/all-day rail에 사용한다. role/override는 Phase 8에 남긴다.
- 자동 검증:
  - 최종 `xcodebuild test` result bundle: **33 tests passed, 0 failed, 0 skipped**
  - unsigned Release build: pass
  - ad-hoc signed Debug build: pass
  - `codesign --verify --deep --strict`: pass
  - signed entitlement의 app sandbox, Calendar access, get-task-allow: pass
  - built Info.plist의 macOS 14 minimum과 `NSCalendarsFullAccessUsageDescription`: pass
  - `git diff --check`: pass
- 시각 검증:
  - 민감정보가 없는 `/private/tmp` 전용 provider로 1,360×840 Week를 offscreen render했다.
  - 15개 샘플에서 calendar별 blue/pink rail, 3열 timed overlap, current-time line, 자정 횡단 card, 10행 all-day의 제한 높이와 scroll container를 눈으로 확인했다.
  - 이 fixture와 PNG는 제품 runtime·저장소에 포함하지 않는다.
- 실계정 실행:
  - 최신 signed app의 `open -n` 실행 요청: pass
  - 사용자의 full access 승인 결과와 실제 `KAOS-TEST`의 Exchange/writable/color 노출, Day/Week/Agenda click·scroll·inspector 상호작용은 **수동 대기**다.
- 보안:
  - password, MFA, OAuth token, tenant/client secret을 요청·저장하지 않는다.
  - runtime에 `KAOS-TEST`나 테스트 일정 내용을 하드코딩하지 않았다.
- 결과: Phase 2 코드·자동·offscreen 표시 checkpoint 완료. Phase 1 실계정 권한 gate는 닫지 않았으며 Phase 3 구현을 막지 않는다.
- 계획 변경: 실제 calendar color snapshot은 source 구분을 위해 Phase 2로 앞당겼다. calendar role·사용자 override·Viewer 설명은 Phase 8에 유지한다.
- 남은 위험: Exchange backend unknown, 실제 TCC 승인 미확인, KC-E1~KC-E4와 외부 변경 실계정 검증, Viewer calendar `blocked`, 실제 창의 VoiceOver/키보드/scroll 수동 QA.

## 2026-07-10 — Phase 3 Local Context DB 구현 및 안전성 gate

- 관련 ADR: ADR-003, ADR-004, ADR-005, ADR-006, ADR-008
- dependency checkpoint:
  - GRDB.swift `7.10.0` exact pin과 `Package.resolved`를 별도 commit `8ed589c`로 고정
  - resolved file만 사용하는 build에서 package resolution 확인
- 변경 파일:
  - `KaosCal/ContextStore`: `AppDatabase`, immutable `v1_context_store` migration, record/domain model, `ContextStore`, event/personal/task repositories, Task Center query, fingerprint
  - `KaosCalApp`, `AppState`, `CalendarShellView`: production DB bootstrap, EventKit fetch batch observe, DB 실패 전역 중단·복구 안내
  - `CalendarModels`, `EventKitProvider`: all-day/floating recurrence local occurrence snapshot과 UI identity
  - `ContextStoreTests`, `CalendarAccessTests`, `CalendarEventLayoutTests`, `AppStateTests`: persistence·identity·bootstrap 회귀
  - ADR-008과 architecture/data model/phase/QA/setup/backup 문서
- 구현:
  - Application Support의 `kaoscal.sqlite`를 `DatabaseQueue`로 열고 migration한다. 실패 시 in-memory로 대체하지 않고 기존 파일을 보존한다.
  - v1은 `event_contexts`, `event_links`, `event_tasks`, `personal_tasks` 네 테이블만 만든다. change log/role/settings는 후속 additive migration으로 이월한다.
  - 단순 선택·빈 notes는 row를 만들지 않고, 첫 notes 또는 event task에서 context+link를 원자적으로 만든다.
  - resolve부터 create/update까지 하나의 write transaction으로 묶고 identifier+occurrence unique index로 동시 첫 저장 중복을 막는다.
  - strong identifier 관찰만 title/time/source/identifier/last-seen snapshot을 갱신한다. exact snapshot과 normalized SHA-256 fingerprint는 자동 연결하지 않는 후보로 남긴다.
  - zoned 반복은 absolute occurrence key, all-day/floating 반복은 local civil occurrence key를 사용한다. detached는 이동된 start가 아니라 원 occurrence anchor를 보존한다.
  - `Date`는 명시적 `.deferredToDate` UTC millisecond TEXT로 고정한다.
  - event task의 none/fixed/relative due와 5년 offset 상한, personal task, Today/Upcoming/Completed 통합 query를 구현한다.
  - hosted XCTest는 `XCTestConfigurationFilePath`를 감지해 production Application Support DB를 열지 않는다.
- 자동 검증 이력:
  - 직전 안정본 전체 회귀: **52 tests, 0 failures**
  - 최신 ContextStore targeted 재실행: **18 tests, 0 failures**
  - calendar/access/layout/context combined 실행은 47개 중 file-reopen fixture의 weak exact-candidate 충돌 1건을 찾아 수정했고, 해당 ContextStore 전체 18개 재실행으로 수정 통과를 확인
  - migration negative FK/CHECK, 동시 첫 저장, 관찰-only move, all-day/floating 시간대·detached, fingerprint fixture, raw Date TEXT, 일반 Date binding, 파일 DB reopen을 포함
- 최종 자동 gate:
  - test-host live DB 차단과 빈 external series fallback을 포함한 최신 전체 회귀: **54 tests, 0 failures, 0 unexpected**, `TEST SUCCEEDED`
  - pinned `Package.resolved`만 사용한 unsigned Release build: `BUILD SUCCEEDED`
  - ad-hoc signed Debug build: `BUILD SUCCEEDED`
  - `codesign --verify --deep --strict`: pass
  - signed entitlement: app sandbox, Calendar access, Debug의 get-task-allow만 포함
  - built Info.plist: bundle `com.adtstack.kaoscal`, macOS 14.0 minimum, full calendar access usage description 확인
  - 전체 회귀 xcresult: `Test-KaosCal-2026.07.10_22-15-04-+0900.xcresult`
- 테스트 격리 사건:
  - 격리 수정 전 hosted XCTest가 direct/sandbox Application Support에 zero-row schema DB를 생성한 사실을 확인했다.
  - 두 DB는 사용자 영역 파일이므로 삭제하지 않았고, 감사 시 네 테이블 row count는 모두 0이었다.
  - 기록한 mtime은 direct `2026-07-10 19:18:24 +0900`, sandbox `2026-07-10 19:20:43 +0900`이며 격리 수정 뒤 최신 54-test 전체 회귀 전후에 모두 불변이었다.
- 미검증/이월:
  - Phase 4 Event Brief/Task Center 실제 UI CRUD와 앱 종료·재실행 수동 흐름
  - 실제 `KAOS-TEST` Exchange identifier churn·detached occurrence
  - missing/orphan lifecycle, change log, backup/export/import/reset
  - full access와 Exchange/writable 실계정 gate는 기존과 같이 대기
- 결과: Phase 3 코드·자동 검증 checkpoint 완료. 실제 UI를 통한 저장·재실행 확인은 Phase 4 수동 gate로 유지하고 Phase 4 구현을 시작한다.

## 2026-07-10 — Phase 4 Event Brief·Task Center 구현 checkpoint

- 관련 ADR: ADR-002, ADR-004, ADR-008, ADR-009
- 변경 파일:
  - `AppState`: private event/filter selection, Brief/notes/Task Center state, local mutation, day/time-zone refresh, strong-only 원본 navigation
  - `EventBriefView`: Before/During/After task CRUD·완료·이동, notes autosave 상태, identity safety, local editable badge
  - `TaskCenterView`: Today/Upcoming/Completed grouping, personal quick-add·due editor, typed event/personal row action, 원본 event source
  - `ContextStore`와 repositories/models: typed Task Center ID, lazy brief load, context-scoped task mutation, idempotent completion, read-only inverse matcher
  - `LocalWorkspaceTests`, `ContextStoreTests`, interval-aware fake provider와 관련 문서
- 상호작용 결정:
  - notes는 700ms debounce하고 선택·local mutation·inactive·종료 전에 flush한다. 같은 event refresh에서는 draft를 유지한다.
  - task title은 Return·focus loss와 완료·section 이동·원본 열기·화면 이탈 전에 commit한다. 실패하면 후속 action을 중단한다.
  - candidate/ambiguous identity에서는 새 context를 만들거나 자동 relink하지 않고 편집을 차단한다.
  - read-only/invitation의 원본 권한과 local Event Brief 편집 가능 상태를 별도 badge로 표시한다.
  - personal due는 생성·수정·제거 가능하며 Today/Upcoming query를 즉시 다시 읽는다. due는 reminder가 아니다.
  - event-linked navigation은 저장 range를 fetch한 뒤 강한 identifier+occurrence가 정확히 하나일 때만 선택한다.
- 감사에서 찾아 수정한 문제:
  - debounce 중 동일 일정 refresh와 다른 local mutation이 notes draft를 덮던 경로
  - 이전 visible-range task가 원본 navigation target fetch를 뒤늦게 덮을 수 있던 경로
  - 완료·이동·navigation 전에 편집 중 task 제목이 사라질 수 있던 경로
  - 일정 선택이 바뀐 뒤 이전 Event Brief row의 `onDisappear`가 새 Brief에서 task를 찾다가 제목을 잃을 수 있던 경로; typed task/context ID 저장으로 교체
  - personal due update 부재, Upcoming quick-add의 잘못된 날짜, filter composer state 손실
  - EventKit move·자정·system time-zone 변경 뒤 Task Center projection이 stale한 경로
- 현재 자동 검증:
  - ContextStore 집중: **25 tests, 0 failures**
  - LocalWorkspace 집중: **15 tests, 0 failures**
  - pinned package 기반 unsigned Debug build: `BUILD SUCCEEDED`
  - lazy selection, autosave/flush, typed routing, CRUD·completion, personal due filter 이동, move refresh, day boundary, out-of-range strong navigation, read-only/invitation local edit 포함
- 최종 자동·빌드·서명 gate:
  - pinned GRDB 7.10.0 기반 최종 전체 회귀: **75 tests, 0 failures, 0 unexpected**, `TEST SUCCEEDED`; `Test-KaosCal-2026.07.10_23-12-13-+0900.xcresult`
  - 최종 전체 회귀 전후 direct/sandbox Application Support DB mtime은 각각 `2026-07-10 19:18:24 +0900`, `2026-07-10 19:20:43 +0900`으로 불변
  - pinned `Package.resolved`만 사용한 unsigned Release build와 ad-hoc signed Debug build: `BUILD SUCCEEDED`
  - `codesign --verify --deep --strict`: pass
  - signed Debug entitlements: `com.apple.security.app-sandbox`, `com.apple.security.get-task-allow`, `com.apple.security.personal-information.calendars` 모두 `true`
  - built Info.plist의 `NSCalendarsFullAccessUsageDescription` 확인
- fixture 시각 검증:
  - 실제 DB·EventKit과 분리한 in-memory DB·fake Exchange provider로 1360×840 Event Brief와 Task Center offscreen 창을 렌더했다.
  - invitation/original 안내와 local editable badge, Before/During/After, notes, Overdue/Today/No date, event/personal source row의 핵심 레이아웃과 clipping 부재를 확인했다.
  - 임시 렌더 test/helper는 확인 뒤 제거했다. material·toolbar와 interaction은 offscreen 결과로 완료 선언하지 않는다.
- 수동 gate 대기:
  - 실제 서명 앱 창의 scroll·keyboard/focus·popover·delete confirmation
  - 실제 앱 종료·재실행 DB 유지, 실제 `KAOS-TEST` event-linked occurrence, Viewer/KC-E6 local-only 확인
- 명시적 이월:
  - event task fixed/relative due 편집 UI와 notification/reminder
  - weak/ambiguous relink, missing/orphan lifecycle, 원본 EventKit write, change log, backup
- 결과: Phase 4 구현과 자동·빌드·서명·fixture 시각 gate는 통과했다. 실제 창 상호작용과 Exchange 실계정 gate는 완료로 선언하지 않고 후속 수동 검증으로 유지한다.

## 2026-07-11 — Phase 5 비반복 원본 일정 편집 checkpoint

- 관련 ADR: ADR-001, ADR-003, ADR-004, ADR-008, ADR-009, ADR-010
- 변경 파일:
  - `CalendarEventEditing.swift`: create/update draft, all-day 배타 범위, reference time zone, preserve-local/preserve-instant, validation·write error
  - `CalendarProvider` / `EventKitProvider`: default writable calendar, create/update/delete, strong re-fetch, fresh snapshot, changed-field patch
  - `AppState`: 단일 editor session, create/edit/delete command, local mutation preflight·rebind, receipt focus와 부분 성공 안내
  - `EventEditorView`: title/calendar/location/time/all-day/time-zone/original notes editor와 delete confirmation
  - `DisplayEvent`: 원본 notes, invitation과 attendee meeting 구분
  - `ContextStore`: mutation context read와 사용자 승인 rebind transaction
  - `CalendarEventEditingTests`, `ContextStoreTests`, fake provider와 Phase 5 정책·QA·호환성 문서
- 쓰기 범위 결정:
  - full access, writable, attendee 없음, 비반복 일정만 Phase 5 원본 write 대상으로 삼는다.
  - 새 일정은 EventKit default, 현재 선택, Exchange, 첫 writable calendar 순서로 초기 calendar를 고른다.
  - linked same-calendar title/time/all-day/time-zone/location/original notes 변경은 editor Save를 승인으로 보고 허용한 뒤 같은 context ID에 receipt snapshot을 rebind한다.
  - linked calendar 이동은 Phase 6, linked 삭제·orphan review는 Phase 7, recurrence/`EKSpan`은 Phase 6으로 이월했다.
  - attendee meeting은 사용자가 organizer여도 Calendar.app 전용이다. invitation과 attendee meeting 표시는 별도로 유지한다.
  - 원본 event notes와 local Event Brief notes를 서로 다른 field와 저장소로 유지한다.
- provider 안전성:
  - 편집 시작 `EKEvent`를 저장하지 않고 같은 long-lived store에서 event ID → calendar item ID → external ID 순으로 다시 찾는다.
  - 원 calendar의 유일한 nonrecurring 후보만 허용하고 지원 필드가 외부에서 달라졌으면 stale 오류로 중단한다.
  - no-op은 save하지 않고 변경된 field만 patch해 unchanged structured location/rich metadata를 보존한다.
  - provider에서도 현재 read-only, attendee, recurrence 상태를 다시 확인한다.
- 시간 의미:
  - all-day editor는 포함 종료를 보여 주되 draft/EventKit은 배타 종료를 사용한다.
  - timed 일정이 정확히 자정에 끝날 때 all-day 변환으로 하루가 추가되던 경계를 수정했다.
  - draft reference time zone을 고정해 UI와 provider validation이 같은 civil 의미를 사용한다.
  - 편집 중 Mac 기본 time zone이 바뀌면 all-day/floating wall components를 현재 기본 zone의 Date로 재구성해 선택한 civil 날짜·시각을 유지한다.
  - stale time 비교도 zoned는 absolute instant+zone, all-day/floating은 civil components를 사용해 기본 zone 변화 자체를 외부 일정 수정으로 오판하지 않는다.
  - preserve-local 결과가 DST gap/overlap이면 Foundation의 자동 보정이나 첫 occurrence 선택을 허용하지 않고 중단한다.
- local 안전성:
  - pending notes 저장 실패와 weak/ambiguous identity에서는 editor를 열지 않는다.
  - active editor가 있으면 toolbar/`⌘N`과 AppState 양쪽에서 두 번째 session을 차단한다.
  - linked rebind는 notes/tasks를 유지하는 단일 SQLite transaction이며 unique 충돌과 missing context가 다른 row를 바꾸지 않음을 검증했다.
  - EventKit 성공 뒤 rebind 실패는 원본 성공을 숨기지 않고 sheet에 부분 성공·local 보존 오류를 남긴다.
  - receipt focus의 external identifier fallback은 non-empty identifier가 있을 때만 사용해 nil끼리 잘못 선택하지 않게 했다.
- UI 안전성:
  - floating toggle/IANA 입력이 Apply·confirmation 전이면 Save를 비활성화한다.
  - attendee meeting/invitation, recurrence, read-only는 inspector에서 원본 잠금 이유를 표시한다. event card는 meeting/read-only lock과 recurrence repeat 상태를 구분하고 local Brief는 계속 편집할 수 있다.
- 최종 자동 검증:
  - `CalendarEventEditingTests`: **18 tests, 0 failures**
  - `ContextStoreTests`: **29 tests, 0 failures**
  - 전체 회귀: **97 tests, 0 failures, 0 unexpected**, `TEST SUCCEEDED`
  - 최종 result bundle: `Test-KaosCal-2026.07.11_00-27-42-+0900.xcresult`
  - production direct/sandbox DB는 테스트 전후 각각 `2026-07-10 19:18:24 +0900`, `2026-07-10 19:20:43 +0900`, 모두 `110592 bytes`로 불변
- 빌드·서명 gate:
  - pinned GRDB 7.10.0 기반 unsigned Release: `BUILD SUCCEEDED`
  - ad-hoc signed Debug: `BUILD SUCCEEDED`
  - `codesign --verify --deep --strict`: pass
  - signed Debug entitlement: app sandbox, get-task-allow, calendars 모두 `true`
  - built Info.plist의 `NSCalendarsFullAccessUsageDescription` 확인
- 수동 gate 대기:
  - 실제 macOS full calendar access 승인·복구
  - `KAOS-TEST`의 Exchange source/writable/calendar color 노출
  - Calendar.app 비반복 create/update/delete, all-day, floating/zoned round-trip
  - 실제 EventKit identifier churn, Exchange 서버 정규화, 외부 변경 충돌
  - attendee meeting/초대에 변경 메일이 발생하지 않는지 확인
  - shared read-only Viewer는 미준비로 Phase 8 gate 전까지 `blocked`
- 결과: Phase 5 코드·자동·Release·ad-hoc 서명 checkpoint를 통과했다. fake provider 자동 검증을 실제 Exchange save/remove 지원으로 해석하지 않으며, 위 실계정 수동 gate는 계속 열린 상태다.

## 2026-07-11 — Phase 6 안전 계약과 Exchange 수동 gate 준비

- 관련 ADR: ADR-003, ADR-004, ADR-008, ADR-009, ADR-010, ADR-011
- 상태: **문서·설계 checkpoint / Phase 6 구현·자동·실계정 검증 결과 미선언**
- 사용자 보고와 독립 검증 구분:
  - 사용자는 2026-07-11 macOS 전체 캘린더 접근을 허용했다고 보고했다.
  - 이 보고만으로 최신 서명 앱의 `Full calendar access`, EventKit fetch, `KAOS-TEST`의 Exchange source·writable·color, Calendar.app round-trip을 pass 처리하지 않는다.
  - Exchange backend 종류는 계속 unknown이고 shared read-only Viewer는 미준비다.
- Phase 6 결정:
  - 반복 update/move/delete는 `이번 일정`(`thisEvent`) 또는 `이번 이후`(`futureEvents`)의 명시적 scope와 최종 impact Confirm 전에는 provider를 호출하지 않는다.
  - detached occurrence의 future scope, complex recurrence의 future/rule 변경, attendee meeting/invitation은 Calendar.app 전용 또는 사전 차단이다. complex recurrence의 `thisEvent` ordinary-field patch는 recurrence rule을 보존하는 조건으로 허용한다.
  - Phase 6의 첫 안전 범위는 linked future-series write를 전부 EventKit 호출 전에 차단한다. 후속으로 열려면 영향받는 모든 local context의 strong reconciliation plan이 필요하고 weak·ambiguous·missing이면 계속 중단한다.
  - linked safe move는 receipt로 기존 context ID를 rebind하고 notes/tasks를 보존한다. linked delete는 Phase 7 orphan review까지 계속 차단한다.
  - immutable v1 뒤에 `v2_event_change_log` additive migration을 두고 change type, scope, versioned before/after, undo state와 원본 change self-reference를 기록한다.
  - Undo는 persistent history rollback이 아니라 같은 process session의 직전 linked nonrecurring `single` calendar/time write 한 건에만 허용한다. unlinked·details-only·반복 scope·detached occurrence·delete·재실행 뒤 history-only Undo는 금지한다.
  - EventKit과 SQLite는 원자적이지 않다. linked rebind와 log append끼리만 하나의 SQLite transaction이며 EventKit-only 성공은 부분 성공으로 표시한다.
- 계획된 자동 gate:
  - additive migration FK/CHECK/index와 v1 불변성
  - versioned payload time/recurrence round-trip
  - impact preview와 Confirm 전 provider/log 0회
  - linked move/context 보존, unsafe future 사전 차단, rebind+log rollback
  - available→superseded, undone+restored와 session token 무효화
- Phase 5 기준 수동 gate build evidence — Phase 6 build나 화면 pass가 아님:
  - source commit: `4d19ffa`
  - 환경: macOS 26.4.1, Xcode 26.6 / Build 17F113
  - command: `xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalPhase5ManualGate -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES build`
  - result: `BUILD SUCCEEDED`
  - artifact: `/private/tmp/KaosCalPhase5ManualGate/Build/Products/Debug/KaosCal.app`
  - bundle/version/minimum: `com.adtstack.kaoscal` / `0.1.0` / macOS `14.0`
  - CDHash: `61826f59004e96593e76e38bfe571d74f90a1d79`
  - `codesign --verify --deep --strict`, sandbox·calendars·Debug get-task-allow entitlement, full-access usage description: pass
  - app launch, screen, TCC state, `KAOS-TEST` read/write, Calendar.app/Exchange round-trip: **not run in this entry**
  - build 뒤 direct/sandbox production DB mtime·size는 Phase 5 기록과 동일해 불변
- 문서 변경: README, ADR-011/index, phase plan, architecture, data model, design system, EventKit decisions, QA, Exchange compatibility, v1 scope, developer setup, implementation log
- 결과: Phase 6의 구현 전 안전 경계와 검증 기준을 기록했다. 코드·test count·signed Phase 6 build·실계정 pass는 실제 결과가 생긴 뒤 별도 항목으로 추가한다.

## 2026-07-11 — Phase 6 recurrence·safe move·change log·session Undo checkpoint

- 관련 ADR: ADR-003, ADR-004, ADR-008, ADR-009, ADR-010, ADR-011
- 상태: **코드·자동·Release·ad-hoc 서명 checkpoint 통과 / 최신 창·실계정 Exchange 수동 gate 대기**
- 구현:
  - 기본 일·주·월·년 recurrence, interval·주간 요일·종료 조건과 손실 없는 EventKit mapping을 추가했다. 복잡·다중 rule은 unsupported snapshot으로 보존한다.
  - 반복 update/delete에는 기본값 없는 `thisEvent`/`futureEvents` scope를 요구하고 위험한 변경은 immutable impact preview의 Confirm 뒤에만 실행한다. `thisEvent` detach 가능성을 명시하고 detached future, complex future/rule 변경, attendee meeting을 사전 차단한다.
  - series/occurrence strong identifiers와 zoned instant 또는 all-day/floating civil anchor로 최신 occurrence를 다시 찾고 stale 지원 필드가 같을 때 변경 필드만 patch한다. 저장 뒤 occurrence receipt를 재탐색한다.
  - post-save occurrence receipt를 확정하지 못하면 이미 저장된 부분 성공으로 처리해 editor/review를 닫고 refresh하며 동일 명령을 재시도하지 않게 한다. local Brief·log·Undo는 만들거나 지우지 않는다.
  - linked move·시간 의미 변경은 기존 context ID·notes·tasks를 유지하고 receipt rebind와 change-log append를 한 SQLite transaction으로 수행한다. 모든 linked future와 linked delete는 각각 multi-context reconciliation·Phase 7 review 전까지 차단한다.
  - immutable `v1_context_store` 뒤에 `v2_event_change_log` additive migration, versioned before/after payload, scope·undo state·self-reference 제약과 index를 추가했다.
  - 같은 process session의 직전 linked 비반복 `single` calendar/time mutation 한 건만 fresh after-snapshot 검증 뒤 one-shot Undo할 수 있다. 성공 시 original을 `undone`으로 바꾸고 `restored` row와 context rebind를 atomic 처리한다.
  - recurrence editor, scope picker, impact review, Event Brief notes/task/history 요약과 inspector Undo control을 구현했다.
- 최종 자동 검증:
  - `CalendarEventEditingTests`: **28 tests, 0 failures**
  - `ContextStoreTests`: **34 tests, 0 failures**
  - `Phase6AppStateTests`: **9 tests, 0 failures**
  - 전체 회귀: **121 tests, 0 failures, 0 unexpected**, `TEST SUCCEEDED`
  - result bundle: `/tmp/KaosCalPhase6Root/Logs/Test/Test-KaosCal-2026.07.11_01-17-51-+0900.xcresult`
  - 마지막 보완은 기존 all-day/floating recurrence가 reference-zone drift만으로 rule 변경으로 오인되지 않게 새 rule의 civil end rebase와 기존 rule 보존을 분리했으며 집중 37-test와 전체 회귀를 다시 통과했다.
- 독립 검토:
  - recurrence boundary/rebase, EventKit scope·재탐색·stale/no-op, confirm/cancel/double-submit, linked rebind/log transaction, session Undo, v2 migration을 별도 감사했다.
  - 최종 코드 diff에서 남은 P0/P1 없음, `git diff --check` 통과 판정을 받았다.
- 빌드·서명 gate:
  - pinned GRDB 7.10.0 기반 unsigned Release: `BUILD SUCCEEDED`
  - Release artifact: `/private/tmp/KaosCalPhase6Release/Build/Products/Release/KaosCal.app`
  - ad-hoc signed Debug: `BUILD SUCCEEDED`
  - signed artifact: `/private/tmp/KaosCalPhase6Signed/Build/Products/Debug/KaosCal.app`
  - CDHash: `e7d886091b26eab3b00e465c587c5ddbef9f83c2`
  - `codesign --verify --deep --strict`: pass
  - entitlements: app sandbox, calendars, Debug `get-task-allow` 모두 `true`
  - built Info.plist: bundle `com.adtstack.kaoscal`, version `0.1.0`, minimum macOS `14.0`, `NSCalendarsFullAccessUsageDescription` 확인
- production DB 경계:
  - 자동 test 직후 direct DB `/Users/tylor/Library/Application Support/KaosCal/kaoscal.sqlite`는 `1783678704|110592`, sandbox DB `/Users/tylor/Library/Containers/com.adtstack.kaoscal/Data/Library/Application Support/KaosCal/kaoscal.sqlite`는 `1783678843|110592`로 test 전과 동일했다.
  - 이후 signed Phase 6 app을 직접 실행하자 direct DB는 그대로였고 sandbox DB만 `1783678843|110592`에서 `1783700481|126976`으로 변경됐다. 이는 첫 production bootstrap이 additive migration을 적용한 결과다.
  - sandbox DB를 read-only로 확인한 결과 `integrity_check = ok`, foreign-key violation 0건, migration은 `v1_context_store`, `v2_event_change_log`, `event_change_log` row는 0건이었다. 기존 local content 본문은 읽거나 수정하지 않았다.
- 최신 창·Exchange gate:
  - 사용자는 macOS 전체 캘린더 접근을 허용했다고 보고했다.
  - Orca computer-use runtime과 accessibility·screenshots 권한은 ready/granted였지만, 기존 KaosCal 창은 `visible windows but no accessibility window`로 읽지 못했다. 정확한 Phase 6 process는 bootstrap됐으나 별도 window가 잡히지 않았고 window screenshot도 생성되지 않았다.
  - 이번 gate에서 `KAOS-TEST` 또는 다른 calendar에 fixture create/update/delete를 수행하지 않았다. 최신 서명 창의 `Full calendar access`, Exchange source·writable, recurrence span, identifier churn과 Calendar.app round-trip은 계속 **not verified**다.
- 문서 변경: README, ADR-011/index, phase plan, architecture, data model, design system, EventKit decisions, QA, Exchange compatibility, v1 scope, developer setup, implementation log
- 결과: Phase 6 코드·자동·Release·ad-hoc 서명·production additive migration checkpoint를 통과했다. fake provider와 local DB 검증을 실제 Exchange 지원으로 해석하지 않으며, 다음 수동 gate는 정확한 최신 창에서 `KAOS-TEST`를 확인한 뒤에만 전용 fixture로 실행한다.

## 2026-07-11 — Outlook 서버 QA와 로컬 EventKit TCC gate 분리

- 관련 ADR: ADR-001, ADR-003, ADR-010, ADR-011
- run: `20260711-1512-7C4E`
- 테스트 캘린더 결정:
  - source: `KAOS-TEST`
  - destination: `일정`
  - 사용자가 두 캘린더의 고유 QA fixture write를 허용했으며 새 destination calendar를 만들지 않는다.
- 서버 preflight:
  - 두 exact-name match가 각각 하나이고 editable·distinct·same owner임을 확인했다.
  - mailbox time zone은 `Korea Standard Time`으로 반환됐다.
  - connector가 MSA 제한을 보고했으므로 이 결과로 Exchange Online, 같은 Mac의 EventKit account 또는 `EKSourceType.exchange`를 판정하지 않는다.
- Outlook connector 서버 결과:
  - source nonrecurring fixture create → fetch → update: **pass**
  - destination independent write: **pass**. source에서 destination으로 실제 move한 결과가 아니다.
  - Pacific time zone fixture → Korea time zone update와 UTC normalization: **pass**
  - 종료가 있는 weekly recurrence와 occurrence 5개 조회: **pass**
  - `this_instance` exception: **pass**
  - `this_and_following`: connector가 필수 `originalStart`를 제공하지 않아 mutation 전에 **fail**. 원본은 바뀌지 않았고 추측 입력으로 재시도하지 않았다.
  - cross-calendar move: move API가 없어 **not tested**
  - all-day: create schema에 `isAllDay` 입력이 없어 **not tested**
  - search: MSA mailbox에서 지원되지 않아 bounded list fallback으로 exact run marker만 확인했다.
- cleanup:
  - run에서 만든 exact 네 fixture만 mutation 응답 식별자로 삭제: **pass**
  - cleanup 직후 bounded list를 두 차례 실행하고 최종 작업 종료 전 지연 재확인을 한 번 더 수행했다. 세 번 모두 source/destination 잔여가 `0/0`이었다.
  - 기존 calendar event는 수정·삭제하지 않았다.
- 로컬 EventKit gate:
  - 최신 서명 host의 authorization은 `notDetermined`였다.
  - full-access 요청은 macOS prompt UI를 사용할 수 없어 중단했고 local fixture write는 0회였다.
  - TCC full access, EventKit `.exchange` source, `allowsContentModifications`, Calendar.app round-trip, identifier churn·series split은 **blocked / pending**이다.
- 증거·비밀정보 경계:
  - password, MFA, token을 앱·환경변수·저장소에 넣지 않았다.
  - raw calendar/event ID, account/email, owner와 source title은 저장소 문서·프로젝트 로그·commit에 복사하지 않았다. connector session의 응답 식별자는 exact cleanup에만 사용했다.
- 재현 가능한 로컬 preflight:
  - `ManualEventKitQATests/testManualExchangeGate`를 test target에 추가했다. 기본 실행은 provider 생성 전에 skip하고 `inspect` mode만 허용한다.
  - 이 preflight는 access prompt와 write를 호출하지 않으며 report에서 raw calendar identifier와 source title을 제외한다.
- 최종 자동·DB gate:
  - 전체 **122 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. skip은 위 read-only manual gate 하나다.
  - 전체 test 직전·직후 direct/sandbox `kaoscal.sqlite`와 각각의 `-wal`/`-shm` 존재 여부, mtime, size, SHA-256을 비교했고 모두 불변이었다.
  - 두 DB는 서로 같은 내용이며 migration 2개, 업무 table 0 rows, `integrity_check=ok`, foreign-key violation 0이었다.
  - 과거 Phase 6 기록 뒤 direct DB의 mtime·size가 02:30 수동 host 실험 구간에 바뀐 사실은 확인했지만 원인은 소급 귀속할 수 없다. 내용 손상은 없으며, 이번 전후 불변 gate만 현재 증거로 사용한다.
- 최종 Release gate:
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`인 ad-hoc Release build **pass**.
  - `codesign --verify --deep --strict` **pass**, hardened runtime·app sandbox·Calendar entitlement와 full-access usage description 확인, `get-task-allow`·XCTest plug-in 없음.
  - 현재 검증 artifact는 `/private/tmp/KaosCalFinalRelease`이며 이전 임시 artifact를 최종 증거로 재사용하지 않는다.
- 변경 문서: README, phase plan, developer setup, Exchange compatibility, QA checklist, implementation log, ADR-001
- 결과: 서버 측 제한된 CRUD·time-zone·recurrence·cleanup은 통과했다. 서버 pass와 로컬 EventKit pass는 별도이며, 실제 move·all-day·`this_and_following`과 EventKit/Calendar.app이 남아 있어 Exchange 지원 완료를 선언하지 않는다.

## 2026-07-11 — FinalRelease 로컬 EventKit 실사용 gate와 단일 일정 반복 오분류 수정

- 관련 ADR: ADR-001, ADR-003, ADR-005, ADR-010, ADR-011
- 사전 확인 artifact:
  - `/private/tmp/KaosCalFinalRelease/Build/Products/Release/KaosCal.app`
  - CDHash `d5268c733173a42927690013f4441f3004dfa6b8`
  - 앱에서 `Full calendar access`와 `KAOS-TEST`, `일정`이 각각 Exchange source이며 writable인 상태를 실화면으로 확인했다.
- 최초 live run `20260711-1542-A1C9`:
  - `KAOS-TEST`에 `Does not repeat`, Asia/Seoul인 고유 timed fixture를 앱으로 생성했다.
  - 생성 직후와 앱 재시작·재조회 뒤 모두 앱이 반복 배지와 `Recurring occurrence`를 표시하고 편집 시 반복 범위를 요구했다. 비반복 일정이므로 **fail**로 판정했다.
  - 정확한 fixture를 앱에서 삭제했고 bounded Outlook 확인에서 `KAOS-TEST`/`일정` 잔여가 `0/0`이었다. 삭제 전 connector가 이 fixture를 관찰하지 못했으므로 이 최초 run은 원격 동기화 증거로 사용하지 않는다.
  - Calendar.app AppleScript 읽기는 automation 응답이 없어 중단했으며 mutation은 하지 않았다.
- 원인과 계약 수정:
  - 새 비반복 `EKEvent`도 `startDate` 설정 뒤 `occurrenceDate == startDate`를 반환할 수 있는데, 기존 mapper가 `occurrenceDate != nil`을 반복 membership으로 해석했다.
  - provider 경계의 반복 membership을 `hasRecurrenceRules || isDetached`로 한정하고, 비반복 event의 `occurrenceDate`는 `nil`로 정규화한다.
  - 이후 UI·mutation scope·resolve routing은 `DisplayEvent.isRecurring`만 membership 기준으로 사용한다. `occurrenceDate`는 반복 경로 안에서 occurrence identity anchor로만 사용한다.
  - 영속 Undo snapshot의 중복 안전 검사는 손상·구버전 데이터 방어를 위해 유지했다.
- 변경 코드와 회귀:
  - `CalendarProvider`, `EventKitProvider`, `FakeCalendarProvider`의 단일/반복 dispatch를 같은 계약으로 통일했다.
  - macOS의 synthetic occurrence anchor를 재현하는 EventKit 회귀와 noisy anchor가 있는 단일 일정의 no-scope update/delete 회귀를 추가했다.
  - 집중 `CalendarEventEditingTests`: **30 tests, 0 failures**.
  - 전체 **124 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. skip은 read-only 수동 EventKit gate다.
  - 전체 test 전후와 아래 live QA 종료 뒤 direct/sandbox production DB 및 각각의 `-wal`/`-shm` 존재 여부, mtime, size, SHA-256이 모두 동일했다.
- 수정 FinalRelease gate:
  - artifact: `/private/tmp/KaosCalFinalReleaseRecurrenceFix/Build/Products/Release/KaosCal.app`
  - CDHash: `63ded03a9d704976c4ba45340f2748eda9892382`
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release build, hardened runtime, `codesign --verify --deep --strict`: **pass**.
  - entitlement는 app sandbox와 Calendar access만 포함하고 `get-task-allow`는 없다. XCTest plug-in·link도 없다. full-access usage description도 확인했다.
- 수정 후 live run `20260711-1626-B7D2`:
  - 새 CDHash의 macOS full-calendar-access prompt를 사용자가 승인한 범위에서 허용한 뒤 `KAOS-TEST`에 2026-07-11 16:30–17:30 Asia/Seoul, `Does not repeat` fixture를 앱으로 생성했다.
  - 앱 생성 응답: 반복 배지·문구 없음, `Exchange · KAOS-TEST`, `Calendar event · Editable`, Asia/Seoul: **pass**.
  - Outlook server bounded 조회: 같은 고유 표식을 `singleInstance`, `recurrence: null`, 07:30–08:30 UTC로 관찰: **pass**.
  - 앱을 완전히 종료·재시작한 뒤 EventKit에서 다시 읽은 카드·상세·tooltip에도 반복 표시가 없었고, 원본 편집기는 `Does not repeat`와 단일 `Save Changes`만 제공하며 scope 선택을 요구하지 않았다: **pass**.
  - 제목을 단일 일정으로 수정했고 Outlook server에서도 변경 제목, `singleInstance`, `recurrence: null` 유지 확인: **pass**.
  - 편집기에서 scope 선택 없이 `Delete Original Event`를 확인·실행했다. 앱 event count는 0, 지연된 bounded server 확인에서 `KAOS-TEST`/`일정` 고유 표식 잔여는 `0/0`: **pass**.
  - 종료 시 모든 KaosCal 검증 프로세스가 없음을 확인했다.
- 증거·비밀정보 경계:
  - password, MFA, token, account/email, raw calendar/event ID를 저장소나 문서에 기록하지 않았다.
  - 두 run에서 만든 고유 fixture 외 기존 일정은 수정·삭제하지 않았다.
- 남은 경계:
  - 이 run은 signed local EventKit에서 비반복 timed create/refetch/update/delete와 Outlook server 반영을 입증한다.
  - Calendar.app 실화면 round-trip, live all-day, live time-zone change, 실제 반복 series/exception/`this_and_following`, calendar 간 move는 아직 별도 수동 gate가 필요하다.
  - connector의 mailbox 제약 때문에 이 결과만으로 Exchange Online backend 종류를 단정하지 않으며 전체 Exchange 지원 완료도 선언하지 않는다.
- 결과: 최초 live gate가 발견한 실제 오분류를 수정했고, 새 FinalRelease의 단일 Exchange 일정 local→server→local CRUD와 exact cleanup은 통과했다.

## 2026-07-11 — Legacy synthetic-single Brief 호환성과 최종 Release checkpoint

- 관련 ADR: ADR-003, ADR-008, ADR-010
- 최종 검토에서 발견한 업그레이드 경계:
  - 이전 recurrence-fix 전 build가 실제 single Event Brief를 `is_recurring = true`와 occurrence key로 저장했을 수 있다.
  - 수정된 mapper는 같은 이벤트를 `isRecurring = false`, `single:v1`로 읽으므로 기존 strict occurrence match만 두면 강한 identifier가 같아도 notes/tasks가 confirmation-required 상태에 남는다.
  - 이 Mac의 direct/sandbox production DB는 검토 시 `event_links` 0행이어서 현재 사용자 데이터에는 영향이 없었지만, 배포 호환성 자체는 코드로 보완했다.
- 호환성 결정과 구현:
  - schema migration이나 broad weak relink를 추가하지 않는다.
  - 현재 이벤트가 single이고 legacy link가 non-detached recurring이며, event/item/external 강한 identifier 필터 안에서 calendar/title/location/start/end/all-day/time semantics/time zone/local components/fingerprint/series/occurrence anchor가 모두 정확히 같을 때만 기존 context를 연결한다.
  - 정상 load/observe 시 같은 transaction에서 link를 nonrecurring, occurrence/series 없음, `single:v1`로 갱신하고 notes/tasks를 유지한다. navigation match는 read-only다.
  - legacy 구조와 strong identifier가 맞지만 snapshot이 달라졌으면 confirmation-required candidate로 노출하고 자동 연결하지 않는다. identifier 없음은 기존 exact/fingerprint candidate 정책을 유지한다.
- 결정적 회귀 보강:
  - raw `(hasRules, isDetached, occurrenceDate)` 순수 분류 matrix로 synthetic anchor와 membership을 OS 동작과 무관하게 고정했다.
  - scoped overload를 구현하지 않는 최소 provider spy로 `CalendarProviding` 기본 update/delete routing과 recurrence scope 차단을 직접 검증했다.
  - zoned/all-day legacy link 정상화, notes/tasks 보존, navigation read-only, identifier 없음 candidate, snapshot drift의 confirmation-required 반환과 자동 연결 차단을 검증했다.
  - 집중 `CalendarEventEditingTests` **33 tests**, `CalendarEventEditingTests + ContextStoreTests` **72 tests**, 모두 0 failures.
  - 전체 **132 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 최종 결과 bundle은 `/private/tmp/KaosCalRecurrenceCompatFinal.xcresult`다.
  - 전체 test 직전·직후 direct/sandbox production DB와 각각의 `-wal`/`-shm` 존재 여부, mtime, size, SHA-256이 완전히 동일했다.
- 최종 Release gate:
  - artifact: `/private/tmp/KaosCalFinalReleaseCompat/Build/Products/Release/KaosCal.app`
  - CDHash: `511a11258d95a49c826b49dc463a79039707807e`
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**.
  - entitlement는 app sandbox와 Calendar access만 포함하고 `get-task-allow`는 없다. XCTest plug-in·link 없음, full-access usage description도 확인했다.
  - Exchange fixture write를 다시 만들지 않았다. 실계정 비반복 CRUD 증거는 직전 CDHash `63ded03a9d704976c4ba45340f2748eda9892382` run `20260711-1626-B7D2`에 귀속하고, 최종 artifact의 build/자동 gate와 구분한다.
- 결과: live에서 발견한 recurrence membership 수정에 deterministic test와 legacy Brief upgrade 경로를 더했고, 최종 서명 산출물과 운영 DB 격리 gate를 통과했다. Calendar.app·all-day·실제 recurrence/future split·calendar move의 남은 live 판정은 변하지 않는다.

## 2026-07-11 — Phase 7A lifecycle·After Review와 post-write focus 안전성

- 관련 ADR: ADR-003, ADR-008, ADR-011, ADR-012
- 완성도 재평가:
  - 요청 핵심 범위는 Day/Week/Agenda, all-day·time-zone·recurrence 모델, Exchange 우선 EventKit 경계, Event Brief와 Task Center까지 연결됐다.
  - 이번 단계의 주요 미구현은 Phase 7B/C missing·orphan·relink·linked delete, mini month, backup/settings, app icon, 남은 Exchange/Calendar.app live matrix와 Developer ID/notarization이다.
  - 현재 구현을 막는 사용자 입력은 없다. read-only Exchange fixture, Apple Developer Team과 clean-machine beta는 해당 gate를 열 때 별도 요청한다.
- lifecycle·Task Center 구현:
  - active link의 occurrence별 유효 종료에서 `scheduled ↔ completed`를 파생한다. `now == end`가 완료 경계이며 zoned instant, all-day exclusive end, floating civil components를 각각 보존한다.
  - cancelled/orphaned context와 non-active link는 시간 reconciliation이 덮어쓰지 않고, 미래로 이동한 active 일정은 scheduled로 돌아갈 수 있다. 관찰 파생 전이는 change log를 만들지 않는다.
  - 완료 일정의 Before/During open row는 삭제·자동 완료하지 않고 Today/Upcoming projection에서만 숨긴다. 미완료 After는 기존 목록과 새 `After Review`에 남고 Completed는 모든 section의 완료 이력을 유지한다.
  - Event Brief는 종료된 일정임을 명시하고 새 note/task를 처음 저장한 경우에도 completed 상태가 유지된다.
- post-write focus 회귀 수정:
  - 반복 occurrence들이 series identifier를 공유할 때 앞선 sibling을 잘못 focus할 수 있던 fallback을 제거했다.
  - 전체 snapshot에서 exact display ID를 먼저 찾고, 반복 fallback은 동일 calendar와 instant/civil occurrence anchor를 요구한다. nonrecurring strong-ID fallback은 유지한다.
  - zoned, all-day, floating occurrence와 nonrecurring fallback 회귀를 추가했다.
- 자동 검증:
  - 전체 **145 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**.
  - skip은 read-only calendar가 필요한 명시적 수동 EventKit gate 하나다.
  - result bundle: `/private/tmp/KaosCalPhase7AFull.xcresult`.
  - direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 전체 test 및 exact Release bootstrap 전후 동일했다.
- Release와 bootstrap 검증:
  - artifact: `/private/tmp/KaosCalPhase7ARelease/Build/Products/Release/KaosCal.app`.
  - CDHash: `abfb685b03f1ff919f83a955e5b819e3c6b57df6`.
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**.
  - entitlement는 app sandbox와 Calendar access만 포함하고 `get-task-allow`는 없다. XCTest plug-in·link 없음, full-access usage description 확인.
  - exact Release가 onscreen 1360×840 창을 생성하는 것을 CoreGraphics로 확인했고, 읽기 전용 `Tasks` 메뉴 전환 뒤 앱을 종료해 남은 프로세스가 0임을 확인했다.
  - 비활성 앱의 System Events는 창 수를 0으로 잘못 보고했으나 CoreGraphics window list와 AppKit 로그는 동일 창을 확인했다. 자동화 프로세스에 Screen Recording 권한이 없어 픽셀 캡처는 검은 화면이었으므로 시각 레이아웃 pass로 과장하지 않는다.
  - 이 checkpoint에서는 EventKit/Exchange write를 실행하지 않았다. live 비반복 CRUD 증거는 artifact CDHash `63ded03a9d704976c4ba45340f2748eda9892382`, run `20260711-1626-B7D2`에 계속 귀속한다.
- 결과: Phase 7A 코드·전체 자동·운영 DB 격리·Release·bootstrap checkpoint를 통과했다. Phase 7B/C의 삭제 판정은 일반 fetch 부재가 아니라 전용 strong lookup과 사용자 재확인을 구현한 뒤에만 연다.

## 2026-07-11 — Sidebar mini month 구현과 Release checkpoint

- 관련 ADR: ADR-002, ADR-005, ADR-007
- 동작과 결정:
  - Sidebar 상단에 현재 calendar의 locale·`firstWeekday`·time zone을 따르는 고정 6×7/42일 mini month를 추가했다. DST 구간도 초 단위 증가가 아닌 calendar civil-day 연산을 사용한다.
  - 월 화살표는 mini month의 local browse state만 바꾼다. 날짜 선택은 Day/Week/Agenda를 유지하고 Tasks 또는 선택 없는 상태에서는 Day로 전환하며, 기존 `visiblePeriodDidChange`의 selection 정리·range fetch 경계를 재사용한다.
  - focused/today/인접 월을 fill·ring·강조도와 접근성 value로 함께 구분했다. 날짜 label은 요일과 전체 날짜를 포함하고 각 날짜는 안정적인 civil accessibility identifier를 가진다.
  - 현재 event fetch가 42일 전체를 보장하지 않으므로 불완전 데이터를 `일정 없음`처럼 보이게 할 event dot은 넣지 않았다.
- 회귀와 시각 검증:
  - Sunday/Monday-first, 윤년·12월 경계, New York DST의 23/25시간 간격, LA/Tokyo 날짜 차이, 42개 고유 identifier를 검증했다.
  - 같은 loaded week와 먼 날짜의 selection/fetch 동작, 캐시된 재선택, provider create/update/delete 0회를 검증했다.
  - `MiniMonthView`를 210×240, German locale, Monday-first로 직접 offscreen render해 6행, 인접 월, focused+today 표시와 잘림 없음을 확인했다. 전체 `NavigationSplitView` offscreen render는 sidebar를 만들지 않아 시각 근거로 사용하지 않았다.
  - post-review에서 다른 달을 둘러본 뒤 이미 focused인 같은 날짜를 Today 또는 spillover cell로 다시 지정하면 `onChange`가 동일값을 무시해 local browse가 남는 문제를 발견했다. `@Published`의 모든 assignment를 받는 `onReceive`와 순수 `MiniMonthBrowseState` 동기화로 고치고 같은 날짜 signal 회귀를 추가했다.
  - 렌더 자동 gate는 intrinsic fitting이 210×240 안에 들어오는지와 offscreen bitmap 생성을 함께 검증한다. 테스트용 `NSWindow`에 붙이는 실험은 XCTest process SIGSEGV를 일으켜 제품 실패 근거로 사용하지 않고 제거했으며, 별도로 직접 확인한 210pt bitmap만 시각 근거로 유지했다.
  - 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. post-review 최종 result bundle은 `/private/tmp/KaosCalMiniMonthPostReview.xcresult`다.
- Release와 데이터 안전 gate:
  - artifact: `/private/tmp/KaosCalMiniMonthRelease/Build/Products/Release/KaosCal.app`
  - CDHash: `92e16853c099db014b3f3f2d370d0b57ba44bc90`
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**. entitlement는 app sandbox와 Calendar access만 포함하고 `get-task-allow`는 없으며 XCTest plug-in·link도 없다.
  - exact artifact 경로의 앱이 onscreen 1482×931 창을 만들고 정상 종료 뒤 process 0임을 확인했다.
  - direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 전체 test 및 exact Release bootstrap 전후 동일했다.
  - EventKit/Exchange write를 실행하지 않았다. live 비반복 CRUD 증거는 CDHash `63ded03a9d704976c4ba45340f2748eda9892382`, run `20260711-1626-B7D2`에 계속 귀속한다.
- 결과: 요청된 Day/Week/Agenda와 함께 사용할 compact 날짜 탐색기를 구현하고 자동·시각·Release·운영 DB 격리 gate를 통과했다. 다음 주요 개발 범위는 Phase 7B/C missing·orphan·relink·linked delete, backup/settings, app icon과 남은 live/distribution gate다.

## 2026-07-11 — AppIcon과 초기 브랜드 방향

- 관련 ADR: ADR-005, ADR-006, ADR-013
- 생성과 채택:
  - built-in `imagegen` 경로로 외부 reference 없이 새 square raster를 생성했다. 프롬프트는 macOS AppIcon, calendar grid·layered schedule blocks·single checkmark, midnight navy/steel blue/off-white/warm apricot, 중앙 70% safe area, 16px silhouette, 글자·숫자·watermark·기존 calendar 앱 복제 금지를 요구했다.
  - 생성 원본은 1254×1254 opaque PNG였다. 정사각 비율과 가장자리 uniform background를 확인한 뒤 1024px master와 각 macOS slot을 `sips`로 deterministic resize했다.
  - 채택 이유는 calendar와 Todo가 동시에 읽히고, 기존 accent `#2B7099`와 맞으며, red calendar-page나 특정 날짜에 기대지 않기 때문이다.
- asset catalog:
  - `AppIcon.appiconset`에 16/32/64/128/256/512/1024px을 제공하고 Debug·Release의 `ASSETCATALOG_COMPILER_APPICON_NAME`을 `AppIcon`으로 지정했다.
  - 첫 rendition은 square opaque PNG였고 선언 pixel size와 실제 size가 일치했다. 16·64·128px 직접 확인에서 흰 calendar와 apricot check silhouette이 남았다.
  - 현재는 flattened design 하나를 사용한다. Icon Composer layered/default·dark·tinted variant는 clean-machine beta 전 polish로 남긴다.
- Release gate:
  - 최초 opaque artifact: `/private/tmp/KaosCalIconRelease/Build/Products/Release/KaosCal.app`
  - 최초 opaque CDHash: `d8990eec4462f6662f5cb7676cf844c35f2b8a98`
  - Release가 `AppIcon.icns`와 `Assets.car`를 포함하고 Info.plist에 `CFBundleIconFile = AppIcon`, `CFBundleIconName = AppIcon`을 생성했다.
  - 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 결과 bundle은 `/private/tmp/KaosCalAppIconFinal.xcresult`다.
  - `codesign --verify --deep --strict`, hardened runtime, app sandbox와 Calendar entitlement를 통과했고 get-task-allow·XCTest plug-in/link는 없다.
  - exact Release가 1482×931 onscreen 창을 만들고 정상 종료 뒤 process 0임을 확인했다. NSWorkspace가 app icon을 valid로 읽고 여러 logical 표현을 반환했으며 source catalog는 최대 1024px과 1x/2x slot을 제공한다.
  - direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 전체 test 및 exact Release bootstrap 전후 동일했다. EventKit/Exchange write도 실행하지 않았다.
- compatibility review와 correction:
  - current HIG의 system mask를 macOS 14/15 legacy `.icns`에도 적용된다고 가정한 점을 P1로 발견했다. 최초 opaque artifact는 자동·서명 gate 통과와 별개로 release candidate에서 제외했다.
  - approved artwork를 built-in `imagegen` edit로 flat green 밖의 full-bleed squircle에 넣고, skill의 `remove_chroma_key.py`를 soft matte·despill로 실행했다. alpha bounding box의 6px uniform inset을 crop한 뒤 같은 10개 slot을 다시 만들었다.
  - 현재 rendition은 모두 square alpha PNG이며 실제 size가 선언과 일치한다. 네 corner alpha 0, center 255, 16·64·128·1024px의 squircle과 calendar/check 가독성을 확인했다.
  - 확장 권한 자동 승인 사용량 제한 때문에 corrected asset의 첫 xcodebuild가 거절됐고, sandbox 대체는 SwiftPM/Xcode cache 접근 차단으로 실패했다. 우회하지 않고 중단한 뒤 사용자에게 필요한 승인만 요청했다.
  - 2026-07-12 사용자 승인 뒤 `/private/tmp/KaosCalIconCompatRelease/Build/Products/Release/KaosCal.app`을 새로 빌드했다. CDHash는 `bc2ddd83c9d7f5e1bfd62241b0e02e63b23308b6`이며 strict codesign, hardened runtime, sandbox, Calendar entitlement, usage description, XCTest 비포함을 통과했다.
  - `AppIcon.icns`를 `/private/tmp/KaosCalIconCompat-BC2D.iconset`으로 역추출해 16/32/128/256px 모두 alpha가 있고 네 corner 0, center 255임을 확인했다. Info.plist의 icon file/name과 Assets.car도 확인했다.
  - corrected asset을 포함한 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 최종 result bundle은 `/private/tmp/KaosCalAppIconCompatFinal.xcresult`다.
  - exact Release가 onscreen 1512×949 창을 만들고 정상 종료 뒤 process 0임을 확인했다. direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 test·bootstrap 전후 동일했다.
- 결과: 사용자 브랜드 입력 없이 식별 가능한 KaosCal 표식과 macOS 14/15 legacy `.icns` alpha fallback을 구현하고 최종 자동·Release·bootstrap·운영 DB 격리 gate를 통과했다. 실제 macOS 14/15/최신 Finder·Dock wallpaper contrast와 Icon Composer variant는 이후 clean-machine beta gate다.

## 2026-07-12 — Phase 7B missing·orphan·relink 복구

- 관련 ADR: ADR-004, ADR-005, ADR-008, ADR-009, ADR-011, ADR-012
- 완성도 재평가:
  - Phase 7A 이후 가장 큰 local-data 안전 공백은 외부에서 원본이 사라졌을 때 일반 fetch 누락을 삭제로 오인하지 않으면서 Brief를 복구하는 경로였다.
  - Phase 7B는 이 경로를 구현했고, KaosCal에서 linked 원본 삭제를 시작하는 Phase 7C와 분리했다. 현재 사용자 입력 없이 자동·Release gate까지 진행할 수 있다.
- provider lookup:
  - 저장 link에서 calendar/item/event/external identifier, recurrence membership, zoned instant 또는 all-day/floating civil occurrence anchor와 마지막 관찰 snapshot을 가진 전용 query를 만든다.
  - direct identifier seed와 anchor 주변 bounded predicate를 함께 사용하되 same-calendar strong identifier와 occurrence 의미가 일치할 때만 exact found/cancelled다. 약한 snapshot, 다른 calendar, legacy synthetic recurring→single은 confirmation candidate로만 반환한다.
  - 어느 calendar에서든 strong identifier seed의 recurrence/occurrence가 저장 anchor와 맞지 않으면 `strongIdentifierOccurrenceMismatch` 또는 `recurringOccurrenceUnavailable` inconclusive다. bounded search로 멀리 이동한 detached occurrence를 확정할 수 없거나 recurring seed가 불완전하면 false orphan을 막고 ordinary range fetch 부재도 상태 전이에 사용하지 않는다.
  - 살아 있는 series의 one-off 삭제와 검색 범위 밖 detached move는 EventKit의 first-occurrence seed로 구분할 수 없으므로 automatic orphan을 주장하지 않고 manual exact relink만 제공하는 제한을 문서화했다.
- 두 단계 복구와 UI:
  - 첫 전용 `notFound`는 link만 missing으로 만들고 `Check Again` 전에는 orphan action을 열지 않는다. 별도 재확인의 두 번째 `notFound` 뒤에만 Keep as orphan, manual/exact relink, Delete local Brief를 제공한다.
  - error, candidate, ambiguous, inconclusive는 miss로 세지 않는다. Task Center의 `Local Event Briefs`는 active notes-only와 missing/orphan Brief를 모두 보여 원본 event가 현재 range에 없어도 복구 진입점을 유지한다.
  - 삭제 확인에는 notes/tasks 영향과 Exchange/calendar 원본 불변을 표시한다. local 삭제는 SQLite FK cascade만 사용하며 provider write를 호출하지 않는다.
- transaction과 lifecycle:
  - orphan 보관, strong refresh, cancelled 관찰, explicit relink와 local delete는 각각 단일 GRDB write 경계 안에서 수행한다.
  - relink는 strong identifier, fresh provider exact verification, expected `EventLink` 전체 CAS와 unique preflight를 요구한다. context ID·notes·tasks를 보존하고 `relinked` log를 append하며 이전 session Undo를 supersede한다. stale/deleted/ambiguous/inconclusive 후보와 unique/log insert 실패는 local row와 log를 하나도 바꾸지 않는다.
  - v1 `EventLink`는 original EventKit notes를 저장하지 않았으므로 relink 전 change snapshot의 `originalNotes`는 unavailable(`nil`)로 기록하고 local Brief notes를 원본 notes처럼 대체하지 않는다. schema migration은 추가하지 않았다.
  - provider cancelled evidence는 context cancelled를 보존하며, 이후 동일 occurrence의 fresh exact found는 새 positive evidence로 scheduled/completed를 다시 계산한다. 시간 경과만으로 cancelled/orphaned를 자동 덮어쓰는 규칙은 그대로 금지한다.
- 자동 검증:
  - 최종 전체 **175 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**.
  - result bundle: `/private/tmp/KaosCalPhase7BFinal-20260712-0155.xcresult`.
  - occurrence matcher, cross-calendar/shape mismatch guard, 첫/두 번째 miss, error/candidate/inconclusive, cancellation recovery, stale expected-link CAS, stale sheet reconciliation, notes-only entry, manual selection, 식별자 없는 후보, unique/log insert rollback, notes/tasks 보존, immediate Event Brief reload, local delete provider write 0회를 포함한다.
- Release·데이터 안전 gate:
  - artifact: `/private/tmp/KaosCalPhase7BFinalRelease/Build/Products/Release/KaosCal.app`.
  - CDHash: `f3b30718434641dbbd2dbec90f82581342d47506`.
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**. entitlement는 app sandbox와 Calendar access만 포함하고 get-task-allow·XCTest plug-in/link는 없다.
  - exact artifact가 1482×931 onscreen 창을 만들었고 Apple event로 정상 종료한 뒤 process 0이었다.
  - direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 전체 test 및 exact Release bootstrap 전후 동일했다. 두 DB 모두 integrity `ok`, foreign-key violation 0, migration `v1_context_store`·`v2_event_change_log`를 확인했다.
- 남은 gate:
  - 실제 Exchange/Calendar.app 외부 삭제·동기화 지연·identifier churn, candidate 재연결과 recovery sheet 전체 시각 상호작용은 수동 gate다. live fixture write는 이번 자동 checkpoint에서 실행하지 않았다.
  - 이 Phase 7B checkpoint 당시 KaosCal 내 linked original delete, 저장 link 기반 delete change snapshot과 EventKit 성공 뒤 local 부분 성공 처리는 Phase 7C까지 잠겨 있었다. 현재 구현·검증 상태는 바로 아래 Phase 7C 항목이 대체한다.

## 2026-07-12 — Phase 7C linked original delete review·finalize

- 관련 ADR: ADR-005, ADR-010, ADR-011, ADR-012
- review와 UI:
  - active linked Brief의 notes 글자 수와 읽을 수 있는 본문, Before/During/After task 수·제목, 최근 history, 원본 title/date/calendar와 scope를 read-only preparation으로 고정한다.
  - 첫 delete alert의 `Review Deletion Impact`, review의 Back/Cancel은 provider/SQLite를 바꾸지 않는다. `Delete Original & Keep Brief` final Confirm만 실제 delete 권한이다.
  - 성공 뒤 Task Center row와 `Local Event Briefs`, recovery sheet는 일반 orphan과 구분해 `Original deleted · Local Brief kept`를 표시하고 Relink/local Brief delete 진입점을 유지한다. 표시는 상태쌍만 보지 않고 current-link-generation KaosCal deletion provenance도 요구한다.
- identity와 scope:
  - preparation에서 active `EventLink`와 `EventChangeSnapshot(link:)`을 미리 검증한다. Confirm 직전 현재 mutation context, full expected-link equality와 saved snapshot을 다시 확인하고 provider 성공 뒤 local finalize에서도 같은 CAS를 반복한다.
  - nonrecurring은 change-log `single`, recurring occurrence 하나는 `this_event`다. linked `futureEvents`, attendee meeting/invitation과 read-only 원본은 provider 호출 전에 차단한다.
  - Phase 7B에서 구분할 수 없던 외부 one-off recurring deletion과 달리, KaosCal이 직접 시작한 `thisEvent` deletion은 successful receipt가 positive evidence라 exact context를 finalize할 수 있다.
- local transaction과 history:
  - successful delete receipt 뒤 `finalizeLinkedOriginalDeletion` 한 SQLite transaction에서 context lifecycle `cancelled`, link status `orphaned`, 이전 available Undo supersede와 unavailable `cancelled` log append를 수행한다.
  - 같은 context ID, local notes/tasks, identifiers/time/occurrence/fingerprint snapshot과 `last_seen_at`은 유지한다. delete log before/after는 같은 saved-link snapshot이고 `change_type`이 제거 의미를 전달한다.
  - v1 link는 original EventKit notes를 저장하지 않았으므로 두 payload의 `originalNotes`는 unavailable(`nil`)이다. local Brief notes를 대신 넣지 않는다. 새 log는 unavailable이고 process session Delete Undo도 만들지 않는다.
  - deleted-original provenance는 unavailable `cancelled` log 뒤 `(created_at, rowid)`상 더 최신 `relinked`가 없는 경우다. relink는 과거 출처를 무효화하며, 동일 timestamp에서는 rowid를 tie-break로 사용한다. 이후 외부 전이로 `cancelled + orphaned`가 다시 생겨도 새 KaosCal deletion log가 없으면 deleted-original로 표시하지 않는다.
  - `relinkLocalBrief`는 `relinked` log 삽입 뒤 같은 transaction에서 최종 Brief를 다시 읽어 반환한다. 따라서 함수 반환값과 DB 재조회 모두 과거 deletion provenance가 제거된 동일 snapshot이다.
  - v1의 `cancelled`/`orphaned`, v2의 `cancelled`, 기존 `single`/`this_event` scope와 unavailable Undo를 재사용해 schema migration은 추가하지 않았다. provenance도 기존 history ordering으로 파생한다.
- 부분 성공과 crash window:
  - provider failure 전에는 local mutation/log가 없다. EventKit 성공 뒤 receipt가 모순되거나 final CAS/log transaction이 실패하면 local transaction 전체를 rollback해 false log나 부분 status를 남기지 않는다.
  - 외부 EventKit remove와 local transaction은 원자적이지 않다. 원본은 이미 삭제됐거나 삭제됐을 수 있으므로 editor/review를 닫고 refresh하며 같은 Delete를 재시도하지 않는다. local Brief/notes/tasks 보존을 알리고 자동 원본 재생성이나 Undo를 시도하지 않는다.
  - EventKit 성공과 local finalize 사이 process 종료도 같은 crash window다. 재실행 뒤 Phase 7B의 보수적 missing/orphan recovery가 fallback이며 이를 distributed transaction 성공으로 과장하지 않는다.
- 자동 검증:
  - Phase 7C 신규 회귀는 총 **14 tests**다.
  - review preparation/Back/Confirm, provider 호출 0/1회, `single`/`this_event`, future 차단, saved-link CAS, `cancelled + orphaned`, notes/tasks 보존, identical cancellation payload, no Undo, local failure rollback과 irreversible no-retry message에 더해 deletion provenance, relink 무효화, same-timestamp rowid tie-break와 relink 뒤 외부 cancelled/orphaned 비표시를 포함한다.
  - 최종 전체 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**.
  - result bundle: `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`.
- Release·데이터 안전 gate:
  - artifact: `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`.
  - CDHash: `6b1da198f969cb033946fdb72b2b2e46392310f2`.
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**. entitlement는 app sandbox와 Calendar access만 포함하고 get-task-allow·XCTest plug-in/link는 없다.
  - exact binary를 `XCTestConfigurationFilePath=Phase7CReleaseSmoke`로 production DB open을 차단한 채 5초 이상 실행하고 종료했다. 종료 뒤 process는 0이다. computer-use runtime이 실행 중이지 않아 onscreen tree/창 크기는 이번 checkpoint에서 확인하지 않았다.
  - direct DB `1783704658|126976`, sandbox DB `1783700481|126976`, 양쪽 SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 전체 test 및 safe bootstrap 전후 동일했다. 두 DB 모두 integrity `ok`, foreign-key violation 0, migration `v1_context_store`·`v2_event_change_log`를 확인했다.
- 증거 경계:
  - 이 checkpoint의 delete provider는 fake이고 local 저장소는 test DB다. 실제 Exchange/EventKit fixture write, Calendar.app/Outlook 삭제 반영, recurring deletion exception과 process crash recovery는 실행하지 않았다.
  - 기존 live run `20260711-1626-B7D2`는 local Brief 없는 비반복 CRUD 증거일 뿐 Phase 7C linked delete pass가 아니다.
  - 이 자동 checkpoint에서는 Phase 7C Release·서명·safe bootstrap만 통과했고 EventKit/Exchange write를 실행하지 않았다. 후속 live linked delete 결과는 바로 아래 별도 entry에 기록한다.

## 2026-07-12 — Phase 7C linked original delete live Exchange gate

- 관련 ADR: ADR-001, ADR-003, ADR-005, ADR-010, ADR-011, ADR-012
- run·host:
  - run marker/ID: `20260712-025027-KST`; Asia/Seoul
  - exact signed Release: `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`
  - CDHash: `6b1da198f969cb033946fdb72b2b2e46392310f2`
  - `Full calendar access`와 `KAOS-TEST`·`일정`의 exact-name `Exchange`·writable 표시를 확인했다.
- nonrecurring fixture와 persistence:
  - marker `KAOSCAL-P7C-LIVE-20260712-025027-KST-SINGLE`, 2026-07-12 15:00–16:00 KST, attendee 없음, recurrence 없음
  - Notes 1건, Before/During/After task 각 1건을 만들었고 앱 종료·재실행 뒤 Notes와 총 3개 task가 유지됐다.
  - 첫 alert와 final review에 `Scope: Single event`, Notes와 section별 task 수가 표시됐다. Back을 실행한 경로에는 provider/local write가 없었고 Outlook exact-marker count는 1로 유지됐다.
- live delete 결과:
  - final `Delete Original & Keep Brief`를 정확히 1회 실행했다.
  - KaosCal Task Center가 `Original deleted · Local Brief kept`, Notes, 총 3개 task를 표시했다. Undo는 없고 Relink와 Delete Local Brief 진입점은 남았다.
  - Outlook exact-marker count는 즉시 및 지연 확인에서 0이었고 Calendar.app exact title 검색은 `결과 없음`이었다.
- local DB read-only 증거:
  - sandbox DB를 `query_only`로 열어 `integrity_check`, foreign key, `v1_context_store`·`v2_event_change_log` migration을 확인했고 모두 통과했다.
  - 대상 context/link는 1/1로 남아 lifecycle/status가 `cancelled`/`orphaned`였다. Notes가 존재하고 task는 3개, Before/During/After 각 1개였다.
  - 정확히 1개의 `cancelled`/`single`/`unavailable` log, available Undo 0개, 유효하고 일치하는 before/after payload와 current-link-generation deletion provenance를 확인했다.
  - 보존 대상 combined hash는 live delete 전후 동일했다. 실제 hash 값은 기록하지 않았다.
- 자동 증거:
  - 이 live run은 자동 결과를 대체하거나 새 suite로 계산하지 않는다. Phase 7C 신규 14 tests를 포함한 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**와 result bundle `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`가 그대로 유효하다.
- recurring fixture와 session lock:
  - marker `KAOSCAL-P7C-LIVE-20260712-025027-KST-RECUR`를 attendee 없는 daily series로 서버에 만들었고 `seriesMaster`와 2026-07-12~14 occurrence 3개를 확인했다.
  - KaosCal UI 상호작용 전에 macOS session이 자동 잠겼다. 따라서 recurring `thisEvent` live mutation은 **not tested**이며 제품 failure로 판정하지 않는다. automated recurrence tests의 pass도 변경하지 않는다.
- cleanup·증거 경계:
  - recurring exact series 전체를 Outlook에서 삭제했다. 서버 최종 residue는 single 0, recurring 0이다.
  - single local Brief는 증거로 의도적으로 남겨 두었고 화면 잠금으로 UI-only cleanup을 완료하지 못했다. 다음 수동 세션에서 `Delete Local Brief`를 실행하고 EventKit 원본이 재생성되지 않음을 확인해야 한다.
  - raw calendar/event ID, account/email, Notes·task 본문과 실제 combined hash는 기록하지 않았다. run에서 만든 exact fixture 외 기존 일정은 수정·삭제하지 않았다.
- 결과: nonrecurring linked original delete의 exact Release, EventKit write, Calendar.app·Outlook 제거, local Brief/task 보존과 current-link-generation deletion provenance는 **pass**. recurring `thisEvent` mutation과 retained single local Brief cleanup은 session lock으로 **blocked / manual pending**이며 process crash recovery와 backend 종류도 계속 미판정이다.

## 2026-07-12 — Phase 8 Multi-Calendar Clarity

- 관련 ADR: ADR-001, ADR-003, ADR-005, ADR-008, ADR-010, ADR-014
- 범위·모델:
  - EventKit `CalendarSource`와 `DisplayEvent`를 수정하지 않고 `CalendarRole`, `CalendarDescriptor`, `CalendarSetFilter`, `CalendarWriteRestriction`, `CalendarDuplicateCandidate`를 local/read-only projection으로 추가했다.
  - role은 Work/Personal/Family/Shared/Subscription/Other다. subscribed/birthdays만 현재 source에서 Subscription으로 추론하며 나머지는 Other다. source가 사라지고 explicit override도 없으면 과거 account type을 추측하지 않고 Other로 둔다.
  - All과 역할별 virtual Set은 Day/Week/Agenda `visibleEvents`만 좁힌다. raw fetch·Context observation·Task Center·relink·editor destination은 그대로 유지하고, Set 밖의 선택 전 pending notes를 flush한다. Task Center/relink/duplicate navigation은 필요한 경우 All로 전환한다.
- 영속 저장:
  - immutable v1/v2 뒤 additive `v3_calendar_clarity`를 추가했다. `calendar_preferences`는 calendar identifier PK, source/calendar title snapshot, role CHECK와 created/updated timestamp만 가진다.
  - 단순 EventKit fetch는 row를 만들지 않고 사용자 role 변경만 sparse upsert한다. repository는 fetch/upsert/reopen/delete/reset/count를 제공하며 Calendar provider를 참조하지 않는다.
  - Task Center event source에 저장 calendar identifier를 typed field로 추가해 권한이 없거나 event가 range 밖이어도 explicit role을 투영한다.
- source·permission·duplicate UX:
  - Sidebar에 virtual Set picker와 calendar별 role menu, source/account/editable state와 구체 lock help를 추가했다. Agenda, Day/Week timed/all-day card와 Inspector에는 role/source/restriction을, original editor에는 destination role을 연결했다. Task Center는 저장 calendar identifier로 calendar/source/role만 투영한다.
  - restriction 우선순위는 invitation, attendee, subscription, birthdays, provider read-only다. Inspector 설명과 AppState original-write preflight가 같은 typed value를 사용하고 local Event Brief 편집 가능성을 분리해 알린다.
  - duplicate는 다른 calendar에서 normalized title과 timed start/end 각 15분 이내 또는 같은 all-day civil range가 맞는 항목만 review candidate로 만든다. 동일 strong occurrence는 제외하며 자동 merge·hide·delete·EventKit write를 제공하지 않는다.
  - initial 구현의 card별 전체 재계산 성능 위험을 최종 감사에서 발견해, fetch 때 title group별 candidate index를 한 번 만들고 UI는 event ID로 O(1) 조회하도록 수정했다.
- 자동 검증:
  - role inference/Set, restriction precedence, normalized title·15분 경계·all-day·strong occurrence·deterministic index, v1/v2→v3 보존, invalid role CHECK와 repository reopen을 추가했다.
  - role 변경 persistence와 provider create/update/delete 0회, Set filter와 notes flush/selection, hidden duplicate candidate navigation, subscription/birthdays의 모순된 writable snapshot도 write preflight에서 차단함을 검증했다.
  - 최종 전체 **199 tests executed, 198 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**.
  - result bundle: `/private/tmp/KaosCalPhase8FinalTests-20260712-1415.xcresult`.
  - 전체 test 전후 direct DB `1783704658|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`; sandbox pre-migration DB `1783793410|126976`, SHA-256 `ab2347f7c2de41996d5fd67fd4d34ee6fda890554bee0308156265f0dde154cb`와 WAL/SHM 부재가 불변이었다.
- Release·운영 migration:
  - artifact: `/private/tmp/KaosCalPhase8FinalRelease/Build/Products/Release/KaosCal.app`.
  - CDHash: `6c595445dadfb60588410329222557d00865c222`.
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**. entitlement는 app sandbox와 Calendar access만 포함하며 get-task-allow·XCTest plug-in/link가 없다. full-access usage description과 AppIcon keys도 확인했다.
  - session lock 상태에서 exact Release를 정상 bootstrap하기 전 sandbox v2 DB를 `/private/tmp/KaosCalPhase8MigrationPreflight-20260712-1406/kaoscal-pre-v3.sqlite`로 복사했다. pre-copy SHA-256은 `ab2347f7c2de41996d5fd67fd4d34ee6fda890554bee0308156265f0dde154cb`다.
  - bootstrap 뒤 migration은 v1/v2/v3 순서, integrity `ok`, foreign-key violation 0, `calendar_preferences` 0행이었다. event context/link/task/personal/change-log row count는 1/1/3/0/1이고 각 table SHA3가 migration 전후 같았다. 이는 Phase 7C retained local Brief의 본문을 기록하지 않는 content-preservation 증거다.
  - 최종 코드로 다시 만든 위 CDHash Release도 정상 기동한 뒤 직접 종료했다. 기동 전후 direct DB `1783704658|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 sandbox DB `1783832834|139264`, SHA-256 `7cd91d35ceaa7f04a43c00e88cf1c99d7d8f778ebeffa8c55af0f9f269251d23`가 불변이었다. v1/v2/v3, integrity `ok`, foreign-key violation 0, `calendar_preferences` 0행과 기존 table count/hash도 다시 확인했고 WAL/SHM 없음, KaosCal process 0이다. sandbox 파일 hash의 pre-v3 대비 변화는 schema 추가에 따른 것이며 기존 table content hash는 불변이다.
- 증거 경계·남은 위험:
  - Phase 8 checkpoint는 EventKit read만 수행했고 원본 event/calendar write와 role live mutation을 실행하지 않았다. role write 0회는 fake-provider 자동 검증이며 `calendar_preferences`가 0행인 정상 bootstrap도 단순 조회가 row를 만들지 않는다는 증거다.
  - macOS session이 잠겨 210pt Sidebar, 긴 한국어/source명, 44pt overlap card의 repeat/duplicate/lock 조합과 Inspector/VoiceOver 순서를 실화면으로 확인하지 못했다.
  - shared read-only Exchange Viewer calendar가 없어 provider-reported reason의 live 판정도 blocked다. custom saved Set, `No calendars assigned to Work` 같은 role 전용 empty-state copy, color/name override와 자동 duplicate 처리는 Phase 8 완료 범위에 포함하지 않는다.
- 결과: Phase 8 구현·자동·signed Release·운영 additive migration은 **pass**. live visual과 shared read-only Exchange는 **manual pending**이며 이 둘을 자동 결과로 대체하지 않는다.

## 2026-07-12 — Phase 9 Backup / Settings와 최종 데이터 안전 감사

- 관련 ADR: ADR-001, ADR-005, ADR-006, ADR-008, ADR-015
- 범위·파일:
  - `AppDatabase`에 live `DatabaseWriter`의 SQLite online snapshot과 같은 writer 대상 restore를 추가하고, `ContextStore`가 `LocalDataBackupService`를 소유하게 했다. 실행 중 DB 파일이나 WAL/SHM을 filesystem copy/replace하지 않는다.
  - `LocalDataBackupService`는 수동 export, inspect, whole-store import와 six-table reset을 제공한다. store-only ZIP root는 `manifest.json`과 `kaoscal.sqlite` 두 entry뿐이며 manifest format v1은 app/schema/migration/timestamp, DB byte count·SHA-256과 privacy flag를 기록한다.
  - `AppState`는 pending notes flush, editor/recovery/Undo/다른 operation gate, background maintenance lock과 성공 뒤 local projection reload를 담당한다. import/reset 전 자동 ZIP과 raw rollback snapshot을 만들고, restore와 rollback이 모두 실패하면 `.quarantined`로 전환해 local/provider mutation과 refresh를 재시작 전까지 차단한다.
  - `LocalDataSettingsView`와 Settings scene을 추가했다. export/import file panel, destructive import 확인, 정확한 `RESET` 입력 sheet, active DB 경로/Finder 열기, 포함 범위·plaintext·무검열 경고를 표시한다.
  - App Sandbox 밖의 명시적 Open/Save panel URL만 `com.apple.security.files.user-selected.read-write`로 읽고 쓴다. import/reset 전 recovery ZIP은 app container의 Application Support `Backups`에 둔다.
- strict archive·schema 안전 경계:
  - manifest 64 KiB, SQLite 128 MiB, archive 129 MiB 상한을 둔다. nested/duplicate/path traversal/symlink entry, CRC 불일치, deflate, encryption, data descriptor, ZIP64, multi-disk, extra/comment/attribute, trailing byte와 gap/overlap을 거부한다.
  - current migration ledger의 row count·identifier 집합과 전체 `sqlite_master`를 fresh current schema와 정확히 비교한다. `sqlite_*` 이름으로 숨긴 trigger/view와 data-only 미래 migration ledger도 거부한다. integrity/FK 결과는 첫 오류만 읽어 공격성 DB의 출력 증폭을 제한한다.
  - manual export destination은 live DB와 `-wal`/`-shm`/`-journal`, hard link, symlink parent, 대소문자 비구분 volume과 file resource identity까지 비교하고 실제 write 직전에 다시 검사한다.
  - import는 active DB를 바꾸기 전 archive/hash/schema/integrity/FK를 검증하고 자동 ZIP을 완성한다. 같은 live writer에 restore한 뒤 재검증하며 실패하면 raw pre-operation snapshot으로 rollback한다. reset은 migration ledger/schema를 유지한 채 `event_change_log`, `event_tasks`, `event_links`, `event_contexts`, `personal_tasks`, `calendar_preferences`만 한 transaction에서 비운다.
- 개인정보·호환성 계약:
  - complete EventKit store나 attendee 전체 목록을 별도 export하지 않고 계정 credential/password/MFA/OAuth token 전용 필드도 없다. 그러나 Event Brief/task의 사용자 본문은 검사·redact하지 않으며 linked metadata와 original-notes snapshot도 포함될 수 있다.
  - ZIP과 SQLite는 KaosCal이 암호화하거나 서명하지 않는다. SHA-256은 entry integrity일 뿐 제작자 인증이 아니며 신뢰하는 위치와 직접 생성한 backup만 사용한다. machine name은 manifest에 기록하지 않는다.
  - Phase 9 import는 running build와 application identifier·migration·schema object가 정확히 같은 backup만 허용한다. 향후 v4가 v3 backup을 자동 migration하는 경로, schedule backup, retention pruning과 failed-bootstrap recovery는 구현하지 않았다.
- 자동 검증:
  - `LocalDataBackupServiceTests` 8개: 표준 `unzip -t`, manifest/current schema, same-writer import와 automatic ZIP 재복구, six-table reset과 pre-reset ZIP 재복구, CRC/path/hostile ZIP, extra/hidden schema와 future ledger, live DB/sidecar·hard/symlink destination 차단을 통과했다.
  - `Phase9AppStateTests` 6개: pending notes export, import/reset cache reload와 automatic ZIP 재복구, fake provider create/update/delete 0회, import/reset rollback 실패 session quarantine, healthy file-backed 620×620 Settings bitmap을 통과했다.
  - 최종 전체 **213 tests executed, 212 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**.
  - result bundle: `/private/tmp/KaosCalPhase9FinalTests-20260712-1535.xcresult`.
- Release·운영 데이터 gate:
  - artifact: `/private/tmp/KaosCalPhase9FinalRelease-20260712-1535/Build/Products/Release/KaosCal.app`.
  - CDHash: `4f6eb184110ca317a440c5d640cf0670e4c42753`.
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` ad-hoc Release, hardened runtime, `codesign --verify --deep --strict`: **pass**. entitlement는 app sandbox, Calendar, user-selected read/write 세 개이며 get-task-allow·XCTest plug-in/link가 없다. full-access usage description과 AppIcon keys도 확인했다.
  - exact Release는 1512×949 visible window를 생성했고 두 차례 직접 기동·종료했다. bundle-ID 기반 UI restore 시 이미 등록된 Debug build가 한 번 별도로 기동되어 즉시 종료했으며 exact artifact의 시각 증거로 계산하지 않았다. 최종 KaosCal process는 0이다.
  - direct DB `1783704658|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 sandbox DB `1783832834|139264`, SHA-256 `7cd91d35ceaa7f04a43c00e88cf1c99d7d8f778ebeffa8c55af0f9f269251d23`가 전체 test, exact Release 기동과 위 Debug process 전후 모두 불변이었다. 양쪽 integrity `ok`, FK violation 0, WAL/SHM/journal 부재를 확인했고 sandbox는 v1/v2/v3와 `calendar_preferences` 0행을 유지했다. Phase 9은 새 DB migration을 추가하지 않았다.
- 증거 경계·남은 위험:
  - macOS accessibility permission은 granted였지만 provider가 exact Release의 visible 창을 AX window로 노출하지 않았고 window screenshot도 만들지 못했다. 따라서 Settings/Open·Save panel, scroll 전체 copy와 typed reset의 live interaction은 **manual pending**이며 file-backed offscreen bitmap으로 대체하지 않는다.
  - core restore/post-validation 실패 뒤 실제 rollback을 일으키는 fault injection은 없다. 성공 restore/automatic backup 재복구와 AppState의 주입된 `rollbackSucceeded = false` quarantine은 검증했지만 두 증거를 같은 것으로 과장하지 않는다.
  - 이 checkpoint에서 실제 EventKit/Exchange write를 실행하지 않았다. provider write 0회는 fake-provider 자동 증거이며, 과거 Exchange CRUD/live linked-delete run과 분리한다.
  - 손상 live DB 때문에 app open/migration이 실패한 상태의 backup import recovery는 Phase 10이다.
- 결과: Phase 9 healthy current-schema backup/export/import/reset, strict archive/schema/destination, Settings·privacy, rollback 실패 quarantine, 전체 자동·signed Release·운영 DB 격리 checkpoint는 **pass**. live Settings panel과 failed-bootstrap recovery는 명시적으로 이월한다.

## 2026-07-12 — Phase 9 live Settings visual 후속 gate

- 대상 artifact: `/private/tmp/KaosCalPhase9FinalRelease-20260712-1535/Build/Products/Release/KaosCal.app`, CDHash `4f6eb184110ca317a440c5d640cf0670e4c42753`.
- 실행 방법·범위:
  - run `20260712-1616-KST`에서 Orca를 사용하지 않고 Codex의 macOS `System Events` accessibility와 CoreGraphics window capture로 exact Release를 조작·확인했다.
  - 620×652 `KaosCal Settings`에서 Local Data 전체 scroll, active sandbox DB 경로, Export/Import/Finder/Reset button enabled 상태와 privacy/storage copy를 확인했다.
  - 880×448 `Export KaosCal Backup` panel은 Documents와 기본 이름 `KaosCal-Backup-2026-07-12-1616.zip`, enabled Cancel/Export를 표시했다. 880×448 `Import KaosCal Backup` panel은 선택 전 Cancel enabled, `Choose Backup` disabled를 표시했다.
  - 470×256 reset sheet에서 local data만 제거하고 Calendar/Exchange 일정은 삭제하지 않는다는 경고, `RESET` 입력 전 Delete disabled, 정확한 `RESET` 입력 뒤 Delete enabled를 확인했다.
- 안전 경계:
  - Export와 Import panel, reset sheet를 모두 Cancel로 닫았다. 파일 생성·backup 선택·import·reset과 EventKit/Exchange write는 실행하지 않았다.
  - reset sheet를 다시 열어 visual capture한 뒤에도 Cancel로 닫고 exact Release PID를 직접 종료했다. 최종 `pgrep -x KaosCal` 결과는 process 0이다.
- 시각 증거:
  - `/private/tmp/KaosCalPhase9Settings-Live-20260712-1616.png`
  - `/private/tmp/KaosCalPhase9Settings-Live-Bottom-20260712-1616.png`
  - `/private/tmp/KaosCalPhase9ResetSheet-Live-20260712-1616.png`
- 운영 데이터 재검증:
  - direct DB `1783704658|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 sandbox DB `1783832834|139264`, SHA-256 `7cd91d35ceaa7f04a43c00e88cf1c99d7d8f778ebeffa8c55af0f9f269251d23`가 기준값과 동일했다.
  - 두 DB 모두 integrity `ok`, FK violation 0, WAL/SHM/journal sidecar 0개다.
- 결과: Phase 9의 live Settings layout·scroll·privacy copy·Export/Import panel·typed `RESET` activation gate는 **pass**. 실제 export/import/reset mutation, real rollback failure와 failed-bootstrap recovery는 실행하지 않았으므로 별도 gate로 유지한다.

## 2026-07-12 — Phase 10 문서·운영 기반 정리

- 현재 phase, 최신 suite·Release와 열린 live/manual gate를 `docs/current-status.md`의 단일
  상태 기준으로 분리했다. README, phase plan, developer setup과 ADR의 변동 상태 문구는
  이 문서를 참조하도록 정리했다.
- 사용자용 `docs/user-guide.md`와 `docs/known-issues.md`, root `PRIVACY.md`와
  `SECURITY.md`에 설치·권한·EventKit/local data 소유권, plaintext backup, 제한·우회,
  failed-bootstrap 보존과 미정인 support/legal 경계를 기록했다.
- `docs/release-runbook.md`, `CONTRIBUTING.md`, `CHANGELOG.md`와
  `THIRD_PARTY_NOTICES.md`에 Developer ID/notarization/stapling/package/checksum/clean-user
  smoke/rollback, 개발·test·manual opt-in, version history와 pinned GRDB MIT notice를
  기록했다. Team, certificate, notary profile, support contact와 KaosCal license/EULA는
  결정된 것처럼 채우지 않고 외부 beta blocker로 유지했다.
- `docs/backup-restore.md`에는 앱이 DB를 열지 못할 때 파일을 삭제·교체하지 않고 기존 DB와
  `Backups`를 보존하는 임시 runbook을 추가했다. 이는 아직 없는 Phase 10 self-service
  recovery를 지원 완료로 선언하지 않는다.
- 검증: 모든 로컬 Markdown link 존재, README·CONTRIBUTING·release runbook의 shell fence
  `zsh -n`, `git diff --check`, Xcode project/scheme/target listing을 통과했다. notarytool과
  stapler 명령은 설치된 Xcode help와 대조했고, GRDB notice는 `Package.resolved`의 exact
  revision upstream LICENSE와 일치함을 확인했다.
- 독립 release review에서 DMG Developer ID 서명→notary `Accepted`→stapling 중단 조건,
  기존 사용자 upgrade smoke와 EventKit opt-in의 exact test host
  `build-for-testing`→권한 승인→`test-without-building` 순서를 보강했다. Xcode 26.6에서
  두 test 명령을 직접 실행했고 test host CDHash가 전후
  `f04c5f2e220ab237c9cf8a39e7c5ad772d7b93bc`로 동일함을 확인했다. DMG 실제 제출은
  Developer ID/notary credential이 없어 실행하지 않았으며 배포 blocker로 유지한다.
- 코드·project 설정은 변경하지 않았다. 문서의 전체 test 명령을 다시 실행한 결과
  `/private/tmp/KaosCalReviewTests.xcresult`에서 **213 executed / 212 passed / 1 intentional
  manual-only skip / 0 failures / 0 unexpected**, `TEST SUCCEEDED`를 확인했다. 이 문서
  작업과 재실행이 새로운 기능·live·Developer ID 배포 pass를 만들지는 않는다.

## 2026-07-12 — Phase 10 앱 polish·bootstrap recovery checkpoint

- 관련 ADR: [ADR-015](adr/ADR-015-backup-import-reset-safety.md)
- 변경 파일:
  - `KaosCal/App/KaosCalApp.swift`: bootstrap coordinator, first-run onboarding, `⌘R`
  - `KaosCal/ContextStore/AppDatabase.swift`, `LocalDataBackupService.swift`: default DB URL
    분리, strict bootstrap staging/quarantine/rollback
  - `CalendarShellView.swift`: recovery UI와 Day/Week empty-period copy
  - `LocalDataBackupServiceTests.swift`, `AppStateTests.swift`: 3 recovery logic + 2 bitmap 회귀
  - 사용자/설계/QA/배포 문서와 `BETA-LICENSE.md`, `phase10-blockers.md`
- 구현 안전 경계:
  - 정상 store open 실패에서만 bootstrap recovery를 표시한다. current-schema ZIP의 exact
    archive/manifest/hash/schema/migration/integrity/FK 검사를 staging에서 끝내기 전 live
    SQLite를 건드리지 않는다.
  - 검사 뒤 live DB와 존재하는 WAL/SHM/journal을 같은 고유 `Recovery/Failed-Bootstrap-*`
    폴더로 이동한다. replacement 재오픈/재검증 또는 recovery note 작성 실패 시 새 파일군을
    제거하고 이동한 원본을 역순 rollback한다. EventKit provider는 호출하지 않는다.
  - 다른 schema migration/downgrade, 임의 SQLite, record merge와 backup 없는 destructive
    reset은 제공하지 않는다. 격리 파일은 민감 data로 남기며 자동 삭제하지 않는다.
  - `localContextStoreState.failed`가 실행 중에도 발생할 수 있으므로 bootstrap restore는
    `contextStore == nil`일 때만 main/Settings UI와 coordinator에서 허용한다. 살아 있는
    writer가 있는 session failure는 파일 교체 없이 lock/quit 안내로 분리했고 자동 test로
    healthy writer에서는 recovery가 비활성인지 확인했다.
- 집중 검증:
  - Local Data 12 tests는 valid backup restore와 DB+3 sidecar byte 보존, invalid archive가
    live byte/Recovery를 건드리지 않음, installed validation failure 뒤 네 원본 file byte
    전체 rollback, symlink `Recovery`의 pre-touch 거부를 포함해 통과했다.
  - onboarding 680×560과 recovery 620×520 `NSHostingView` offscreen bitmap/fitting을
    통과했다.
- 실제 창 review:
  - `computer-use`로 중간 ad-hoc Release 첫 창을 읽어 onboarding privacy/local/backup copy와
    accessibility tree를 확인했다. 이때 하단 shortcut이 Continue button을 sheet 밖으로
    밀어낸 것을 발견해 button을 별도 행으로 분리했다.
  - 중간 build 종료 뒤 명시적 Continue 없이 onboarding 완료 key가 저장된 것을 확인했다.
    sheet presentation setter는 scene teardown에도 호출될 수 있으므로 setter write를 제거하고
    explicit Continue action만 완료를 저장하게 수정했다.
  - 수정 뒤 동일 bundle ID의 기존 Xcode dev process가 accessibility window를 소유해 최종
    CDHash app의 재실창을 분리하지 못했다. 사용자 상태일 수 있는 dev process를 강제 종료하지
    않았으며 final live pass로 기록하지 않는다.
- 최종 자동 결과: `/private/tmp/KaosCalPhase10Tests.xcresult`, **220 executed / 219 passed /
  1 intentional `ManualEventKitQATests` skip / 0 failures / 0 unexpected**, `TEST SUCCEEDED`.
- 최종 Release: `/private/tmp/KaosCalPhase10Release/Build/Products/Release/KaosCal.app`, CDHash
  `4d7c1b5ad6dde65666f101cae00bdcb9d5b878ed`. ad-hoc + hardened runtime, strict codesign,
  sandbox·Calendar·user-selected read/write entitlement, version `0.1.0` build `1`, XCTest와
  `get-task-allow` 부재를 확인했다.
- 운영 데이터: direct DB `1783704658|126976`, SHA-256
  `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 sandbox DB
  `1783832834|139264`, SHA-256
  `7cd91d35ceaa7f04a43c00e88cf1c99d7d8f778ebeffa8c55af0f9f269251d23`가 전후 동일하고
  integrity `ok`, FK 출력 없음, WAL/SHM/journal 부재다.
- 결과: Phase 10의 저장소 내 앱 구현·자동·offscreen·ad-hoc Release checkpoint는
  **pass**. 외부 beta 완료는 **blocked/pending**이며 Developer ID/notary/package, 승인된
  EULA와 연락처, clean user, final UI/VoiceOver, 실제 손상 DB recovery와 남은 live
  Exchange/Local Data gate가 필요하다. 상세 목록은
  [phase10-blockers.md](phase10-blockers.md)를 따른다.

## 2026-07-13 — v2 Phase 1(T0·T1) provider checkpoint

- 관련 문서: [T0 Provider abstraction](v2/phase-t0-provider-abstraction.md),
  [T1 Apple Reminders](v2/phase-t1-apple-reminders.md)
- 변경 파일: `DatabaseMigrations.swift`, `TaskProviderModels.swift`,
  `TaskProviderRepository.swift`, `TaskProvider.swift`, `AppState.swift`,
  Settings/App bootstrap, reminders entitlement/usage description, schema expectations
- 구현: additive `v4_task_provider` migration, typed event/personal binding constraint,
  provider account/item cache, calendar destination 저장, Apple Reminders permission/list 및
  create/update/complete/delete adapter, local task mutation 연결, 외부 변경 projection refresh
- 검증: Debug build 성공. 전체 suite **220 executed / 219 passed / 1 intentional
  `ManualEventKitQATests` skip / 0 failures / 0 unexpected**, `TEST SUCCEEDED`.
  result bundle: `/tmp/KaosCalPhase1DerivedData/Logs/Test/Test-KaosCal-2026.07.14_00-19-50-+0900.xcresult`
- 결과: **implemented / live pending**. 실제 iCloud·On My Mac fixture, 권한 철회, cleanup,
  fake provider contract와 Task Center source badge는 후속 gate로 남겼다. T2 이후는 시작하지 않았다.

## 2026-07-15 — 현행 스펙 기준선과 calendar usage 자동 checkpoint

- 관련 문서: [제품·시스템 스펙](specification.md),
  [ADR-017](adr/ADR-017-calendar-visibility-and-availability.md),
  [v2 실행계획](v2-execution-plan.md)
- 문서 변경:
  - 현재 구현을 제품 계약, 데이터 소유권, 기능·비기능 요구사항, 상태 전이, 인수 등급과
    추적성으로 정리한 `docs/specification.md`를 추가했다.
  - calendar/Event Brief/task/provider/reference/backup 경계를 고유 요구사항 ID로 연결하고,
    새 기능은 스펙→ADR→test→implementation→evidence 순서로 진행하도록 규칙을 고정했다.
  - 루트 README와 docs index에서 스펙을 현행 동작·인수 기준의 진입점으로 연결했다.
- 구현 변경:
  - EventKit source identifier로 account를 묶고 calendar별 visibility와 availability blocking을
    역할과 독립된 local policy로 추가했다. 모든 calendar는 기본 visible이며
    subscribed/birthdays만 기본 non-blocking이다.
  - `DisplayEvent`의 availability, canceled와 current-user-declined snapshot으로 blocking을
    계산한다. free/canceled/declined는 제외하고 나머지는 보수적으로 포함하며 겹치거나
    맞닿은 interval을 union한다. raw event observation·recovery·editor destination은 숨김으로
    줄이지 않는다.
  - additive `v8_calendar_usage` sparse preference, Settings의 account별 Show/Block/Role과
    bulk action, Sidebar visibility button/blocking indicator를 구현했다. backup/import/reset이
    새 preference를 보존·정리하며 어떤 설정도 EventKit write를 호출하지 않는다.
- 검증:
  - 스펙의 로컬 Markdown link 26개가 모두 존재함을 확인했다.
  - unsigned Debug 전체 suite:
    **237 executed / 236 passed / 1 intentional `ManualEventKitQATests` skip /
    0 failures / 0 unexpected**, `TEST SUCCEEDED`.
  - result bundle:
    `/tmp/KaosCalCalendarUsageFullTests-20260715-1445.xcresult`
  - calendar usage 자동 범위에는 visibility/blocking 독립 persistence, free/cancelled/declined
    제외, Settings offscreen render, current-schema export/import/reset 회귀가 포함된다.
  - `testCalendarUsageSettingsFitsAndProducesOffscreenBitmap`은 pass했지만 임시
    `calendar-settings.sqlite` cleanup 중 열린 file descriptor unlink libsqlite 경고가 한 번
    출력됐다. production DB는 열지 않았으며 fixture lifetime 정리는 후속 점검으로 남긴다.
  - offscreen test resource lifetime 정리 뒤
    `/tmp/KaosCalCalendarUsageUIFinal-20260715-1450.xcresult`에서 UI test 1/1을 SQLite
    lifecycle 경고 없이 재통과했다. `git diff --check`도 통과했다.
- 결과: 현행 작업 트리의 자동 기준선과 요구사항 추적 문서는 **pass**.
- 남은 위험: 이 실행은 unsigned Debug이며 실제 Exchange/provider, final Settings·Sidebar
  window/VoiceOver, Release signing과 운영 DB 불변을 검증하지 않았다. 해당 항목은
  `implemented / live pending`으로 유지한다.

## 2026-07-15 — mini month 일정 존재 표시 스펙 승인

- 관련 문서: [제품·시스템 스펙](specification.md),
  [ADR-002](adr/ADR-002-calendar-and-task-experience.md),
  [Design System](design-system.md), [QA Checklist](qa-checklist.md)
- 문서 변경:
  - `CAL-007`에 표시 중인 6×7/42일 전체 조회, 본문 snapshot 보존, partial/stale 응답
    금지 계약을 추가했다.
  - `UI-005`에 날짜 숫자 아래 3pt 단일 dot, focused/normal/adjacent 색상,
    `visibility ∩ Calendar Set`, availability blocking과의 독립, multi-day/all-day 배타
    종료와 접근성 count를 추가했다.
  - 초기 mini month의 event-dot 보류는 역사적 사실로 유지하고, ADR·architecture·조회
    결정·QA에 승인된 후속 구현 경계와 인수 시나리오를 연결했다.
- 검증: 문서 diff와 로컬 Markdown link를 검사했다. 코드·테스트 파일은 이 문서-only
  변경 범위에 포함하지 않았다.
- 결과: **설계 승인 / 구현 대기**. 현재 앱은 event dot을 표시하지 않으며 자동·offscreen·
  실창·VoiceOver 통과 근거도 아직 없다.

## 2026-07-15 — saved Calendar Set v9 구현·문서 정합화

- 관련 ADR: [ADR-014](adr/ADR-014-multi-calendar-clarity.md),
  [ADR-017](adr/ADR-017-calendar-visibility-and-availability.md),
  [ADR-018](adr/ADR-018-saved-calendar-sets.md)
- 데이터 계약:
  - additive `v9_saved_calendar_sets`가 `calendar_sets`, `calendar_set_memberships`,
    `calendar_set_selection`을 추가한다. All은 synthetic이라 row를 만들지 않는다.
  - `CalendarSetRepository`가 saved Set CRUD·순서, exact calendar identifier membership,
    singleton selection과 active saved Set 삭제 시 All fallback을 관리한다.
  - identifier가 사라진 membership도 보존한다. source/title 유사성으로 자동 rebind하지
    않고 사용자가 `Replace…` 또는 `Remove`를 명시해야 한다.
- 제품 동작:
  - `CalendarSetFilter`는 All, role별 Smart Role Filter, saved Set을 구분한다. saved Set은
    서로 겹치거나 여러 role을 섞을 수 있다.
  - 표시 식은 `global Enabled ∩ selected Set`이다. globally disable해도 membership은
    삭제하지 않으며 availability blocking은 Set과 독립이다.
  - Settings는 saved Set 생성·rename·delete·reorder, enabled/empty 시작, account별
    Include All/Remove All, membership checkbox와 unavailable Replace/Remove를 제공한다.
    Sidebar와 command menu는 All/saved/Smart Filter를 분리한다.
  - duplicate/relink navigation은 persisted Set을 All로 바꾸지 않고 exact event를 임시
    reveal한다. 후속 review에서 이 동작을 normal filter 밖 event와 성공한 write focus에만
    적용하고, unavailable 판정도 권한 있는 authoritative source state로 제한했다. reset과
    strict backup은 v9 Set/membership/selection을 함께 다룬다.
- 문서 검증:
  - 현행 스펙·데이터 모델·아키텍처·사용자 가이드·QA·backup/privacy/security와 ADR index를
    v9 계약에 맞춰 갱신했다.
  - 저장소 Markdown의 상대 링크 존재 여부와 `git diff --check`를 통과했다. Phase 8/9의
    과거 checkpoint 문구는 역사적 범위로 남기고 현행 계약에는 v9/ADR-018을 연결했다.
- 자동 검증:
  - ContextStore/LocalDataBackupService 집중 suite는 **84 executed / 84 succeeded /
    0 skipped / 0 failed**, action status `succeeded`다. result bundle은
    `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-34-47-+0900.xcresult`다.
  - 전체 suite는 **248 executed / 247 succeeded / 1 intentional
    `ManualEventKitQATests` skip / 0 failed**, action status `succeeded`다. result bundle은
    `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-36-07-+0900.xcresult`다.
  - `xcresulttool` metrics/testsRef의 `testStatus`를 직접 집계했다. migration/CRUD/order/
    exact membership/missing rebind/selection, overlapping·mixed-role·empty Set, global
    Enabled·blocking 독립, duplicate temporary reveal, backup/reset과 Settings offscreen을
    포함한다.
  - 이 실행 뒤 review에서 normal visibility 조건부 reveal, write focus reveal, missing 판정의
    authoritative-state guard 3건이 수정됐다. 위 bundle은 해당 수정 전 checkpoint이며 최종
    판정은 아래 250-test 재실행을 따른다.
  - 수정 후 build와 새 UI/post-write 회귀를 포함한 focused **73 tests / 0 failures**를
    통과했다. result bundle은
    `/tmp/KaosCalCalendarSets/Logs/Test/Test-KaosCal-2026.07.15_18-53-22-+0900.xcresult`다.
  - review 수정 뒤 최종 전체 **250 executed / 249 passed / 1 intentional
    `ManualEventKitQATests` skip / 0 failures**를 통과했다. result bundle은
    `/tmp/KaosCalCalendarSets-Final-20260715.xcresult`다.
- 결과: **구현·최종 자동/offscreen pass / 실제 Exchange·실창·keyboard·VoiceOver pending**.

## 2026-07-15 — Task Provider 상태 복구와 mini month event dot 구현

- 관련 요구사항: [제품·시스템 스펙](specification.md)의 `PRV-009`, `CAL-007`, `UI-005`
- Task Provider:
  - Task Center event task에 provider·account·list와 pending/linked/missing/conflict/
    disconnected 상태를 투영하고 attention 설명과 Resolve 메뉴를 추가했다.
  - missing은 provider 재확인 또는 local 기준 remote 재생성, conflict는 remote 수용 또는
    local 기준 remote 교체, disconnected는 Task Provider Settings와 재확인을 제공한다.
  - 권한 철회 시 해당 provider binding을 disconnected로 투영하고 재승인·exact lookup 뒤
    linked로 복구한다. remote 수용은 local 제목·완료 상태를 명시적으로 갱신한다.
- Mini month:
  - 표시 grid 첫날부터 42번째 날 다음 날까지 별도 summary snapshot을 조회해 본문
    `events`/focused date를 보존한다. reload·scene activation·store change도 현재 summary
    interval을 갱신한다.
  - 완전한 coverage에서만 일정이 겹치는 날짜 숫자 아래 3pt 단일 dot을 표시한다.
    focused는 흰색, 일반은 accent, adjacent month는 낮은 opacity이며 dot 자체는 hit target이나
    accessibility element가 아니다. 날짜 Button value가 정확한 count/loading/unavailable을
    전달한다.
  - `global Enabled ∩ selected Calendar Set`을 적용하고 availability blocking 값은 필터에 쓰지 않는다.
    timed multi-day/all-day는 civil-day overlap과 배타 종료를 따른다.
- 검증:
  - provider conflict remote 수용, disconnect/reconnect와 mini month 42일 DST coverage,
    본문 snapshot 독립, 자정/multi-day/all-day/filter/failure, 210×240 offscreen 회귀의
    focused 4-test·후속 2-test가 통과했다.
  - 최종 전체 suite는 **253 executed / 252 passed / 1 intentional
    `ManualEventKitQATests` skip / 0 failures**, `TEST SUCCEEDED`다. result bundle은
    `/tmp/KaosCalProviderMiniMonth-Final-R3-20260715.xcresult`다.
  - `git diff --check`를 통과했다.
- 결과: **implemented / live pending**. 실제 provider fixture·실창·VoiceOver, 다른 remote
  직접 relink와 durable per-task unlink는 후속 gate다.

## 2026-07-16 — Tasks 안의 Apple Reminders 직접 연결

- 오른쪽 `Details`/`Tasks` segmented control과 `Tasks` 이름은 유지했다.
- `Tasks`와 provider content에 전체 높이 constraint를 적용해 빈 상태나 짧은 목록이
  패널 위쪽 절반에만 배치되지 않게 했다.
- Reminders 권한이 `notDetermined`이면 `Tasks` 첫 진입에서 실제 EventKit full-access
  요청을 실행한다. 거부 상태는 Reminders privacy System Settings로 이동하고,
  미결정 상태에는 수동 `Connect Apple Reminders` fallback을 유지한다.
- 권한 승인 뒤 task가 0개여도 `Apple Reminders connected`를 표시하고, 항목이 있으면
  account/list별 실제 Reminders task projection 위에도 연결 상태를 표시한다.
- 권한 요청 뒤 list/task projection을 검증하는 자동 테스트를 추가했다. 최종 전체는
  **254 executed / 253 passed / 1 intentional `ManualEventKitQATests` skip / 0 failures**,
  `TEST SUCCEEDED`이며 result bundle은
  `/tmp/KaosCalRemindersConnection-Final-20260716.xcresult`다.
- 결과: **implemented / live TCC·Reminders account check pending**.

## 2026-07-16 — Tasks list/source 필터와 가독성 개선

- `Tasks` 이름과 기존 연결 흐름은 유지하고, 수동 count 문구를 전체 폭 `All Lists` menu로
  바꿨다. 선택지는 provider list metadata를 우선해 빈 list와 완료 task만 있는 list를
  보존하고, 일시적 metadata 실패에는 loaded task snapshot을 fallback으로 사용한다.
- Apple Reminders와 Microsoft To Do를 source section으로 나누고 list, account, 불러온 전체 task
  수를 표시한다. 식별자는 표시 이름이 아닌 `(provider, accountKey, listID)` 복합값이라
  같은 raw list ID나 이름을 공유해도 섞이지 않는다.
- 특정 list 선택, Open/Completed/All, 제목·설명 검색, Due date/Title 정렬을 순서대로
  조합한다. list·상태·정렬은 UI preference로 재실행 후 복원하고 검색은 초기화한다.
  OAuth/Task load 중에는 선택을 유지하고, 이후 실제로 사라진 list만 All로 복원한다.
- 같은 provider의 계정별 raw list/task ID 충돌도 account를 포함해 매핑하고 SwiftUI row ID를
  provider·account·list·task 조합으로 만든다. Microsoft list 조회의 일시 실패는 마지막
  성공 metadata를 지우지 않으며, 선택 provider의 빈/loading/error 상태를 다른 provider가
  가리지 않게 했다.
- `.sidebar` List와 중복 disclosure를 제거하고 system background의 ScrollView/LazyVStack,
  명확한 section separator, 2줄 medium title, 1줄 detail, 텍스트·아이콘 overdue 표시로
  읽기 계층을 정리했다. 연결 성공은 상단 초록 상태로 압축하고 오류·복구 안내는 유지했다.
- 자동 검증은 stable provider/list/status/search filtering, 빈 list, rename/delete selection,
  300×600·360×700 light-appearance bitmap을 포함한다. 최종 전체는 **257 executed / 256
  passed / 1 intentional `ManualEventKitQATests` skip / 0 failures**, `TEST SUCCEEDED`이며
  result bundle은 `/tmp/KaosCalTasksFilters-Final-R2-20260716.xcresult`다.
- 결과: **implemented / real Apple·Microsoft menu, keyboard·VoiceOver live pending**.

## 2026-07-17 — Task Provider P1/P2 상태기계·relink·local-only

- 관련 요구사항: `PRV-009`, `PRV-011`, `BAK-005`
- `v10_task_provider_recovery`에서 delete-only pending을 event-task별 create/update/delete
  operation으로 확장하고 account/list/remote/version, 0~3 attempt, 마지막 오류를 저장했다.
  task별 `task_provider_preferences(local_only)`도 추가해 binding/pending을 제거한 뒤에도
  재실행 중 자동 provider 생성이 다시 켜지지 않게 했다.
- linked sync는 저장 binding의 provider/account/list만 사용한다. local/remote projection hash,
  cached baseline과 remote version을 함께 비교해 unchanged, local push, remote apply, conflict를
  구분한다. remote lookup nil은 자동 recreate하지 않고 missing이며 remote-only title/completion/
  due와 binding baseline은 한 SQLite transaction으로 반영한다.
- provider write 전에 pending을 저장하고 실패를 Task Center에 투영한다. 재시도는 사용자 명시
  동작만 허용하고 최대 3회다. crash 뒤 양쪽 결과가 이미 같으면 convergence로 baseline을
  전진시켜 불필요한 conflict를 피한다.
- provider/account/list/task exact 후보를 검색하는 relink sheet를 추가했다. 최종 lookup과 다른
  task 소유 검사를 거쳐 local projection, provider item, 기존 binding/pending/local-only와 새
  binding을 한 transaction에서 교체한다. `Keep Local Only`는 remote task를 삭제하지 않는다.
- calendar destination 변경은 기존 binding을 이동하지 않고 변경 당시 unbound task를
  local-only로 고정한다. 변경 후 만든 task만 새 destination을 사용한다.
- Google의 date-only due는 timed projection hash에서 제외하고 cached remote due 변경을 별도로
  판정한다. Microsoft 설명은 SQLite/backup에 저장하지 않고 프로세스 첫 full delta로 다시
  hydrate한다. OAuth snapshot에는 account key를 넣어 account-local list ID를 구분한다.
- 회귀 테스트 코드는 conflict/no-overwrite, remote apply+delete missing, pending create 재실행+
  local-only, remote 성공 뒤 local delete crash window, exact relink를 포함한다.
- 검증: Debug app `build`, `build-for-testing` 컴파일 성공. 사용자 요청에 따라 테스트 실행과
  실제 provider 계정 fixture는 수행하지 않았다.
- 결과: **code complete through P2 / user test pending**.

## 2026-07-18 — 상용 기능 격차와 C0~C4 후속 스펙

- 관련 요구사항: `COM-001`~`COM-014`
- Fantastical, Apple Calendar, Google Calendar, Outlook, Notion Calendar와 Akiflow의
  공식 기능 문서를 기준으로 현재 KaosCal의 일상 캘린더·협업·task planning·플랫폼·배포
  격차를 분리했다.
- `commercial-feature-roadmap.md`를 Active Product Specification으로 추가했다. 과거 review
  우선순위 `P*`, Phase 0~10, provider `T0~T5`와 혼동하지 않도록 후속 순서를 `C0~C4`로
  고정했다.
- C0는 현재 T0~T5/v10의 test·실계정·접근성·Release gate, C1은 notification, event search,
  full Month, Quick Add/template, conference Join으로 정했다. C2는 수동 task time blocking,
  Command Bar/menu bar, 다중 시간대, Mac-local Set 자동 전환과 EventKit capability 개선,
  C3는 reference/legacy backup과 선택적 확장 재평가다.
- AI 자동 스케줄링, scheduling server, 모바일/Cloud, 직접 Calendar sync, RSVP/attendee write와
  팀 프로젝트는 C4 제외로 분리했다.
- 제품·시스템 스펙, Current Status, Known Issues, User Guide, v1 역사적 범위·제품 원칙과
  문서 인덱스가 새 로드맵을 정본으로 연결하도록 갱신했다. v1의 Apple Reminders 미지원
  문구는 역사적 범위로 보존하되 현재 Event Brief task provider와 Personal task local-only
  경계를 명시했다.
- 검증: 문서 링크·요구사항 ID·Markdown whitespace 정합성 검사. 코드와 schema 변경 없음,
  앱 build/test는 실행 대상이 아니다.
- 결과: **roadmap specified / implementation pending from C0 and C1**.

## 2026-07-18 — 이 Mac 단일 실행·저장, AI·KaosCal Cloud 영구 제외

- 관련 결정: [ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md)
- AI/LLM/ML 기반 생성·요약·분류·추천·검색·자동 배치와 local/remote model 사용을 모두
  제품 범위에서 영구 제외했다.
- KaosCal 계정·backend·cloud database·sync relay·remote config·telemetry, 모바일·웹
  companion과 Event Brief/Task/Calendar Set cross-device sync를 만들지 않는다.
- Calendar는 macOS EventKit, 사용자가 연결한 event task는 이 Mac의 client와 Apple
  Reminders/Google Tasks/Todoist/Microsoft To Do provider 사이에서 직접 동기화한다. KaosCal
  중계 서버는 없고 OAuth token은 Keychain에만 둔다.
- C1 Quick Add는 구조화 입력과 local deterministic template만 남겼다. C3 Reference는
  remote preview 대신 저장 metadata의 local 정리, 선택적 요약은 remote analytics/weather/
  AI 없이 현재 snapshot 기반 local 기능으로 제한했다. C4는 보류가 아니라 영구 제외다.
- Product Principles, Specification, Commercial Roadmap, Architecture, Privacy, Security,
  Distribution, Current Status, Known Issues, User Guide와 README를 같은 경계로 갱신했다.
- 검증: 문서 링크·용어·Markdown 정합성 검사. source/dependency audit에서 AI·analytics
  SDK와 KaosCal backend endpoint는 없고 Swift package는 GRDB 하나임을 확인했다. 코드의
  고정 network endpoint는 Google Tasks, Todoist, Microsoft To Do OAuth/API 범위다. 코드와
  schema 변경 없음, 앱 build/test는 실행 대상이 아니다.
- 결과: **Accepted / local-only product boundary fixed**.

## 2026-07-20 — 오른쪽 Tasks의 Apple Reminders 직접 관리 1차 완성

- 관련 요구사항: `TASK-006`, `PRV-004`, `PRV-009`
- `ProviderTaskListItem`에 SwiftUI용 합성 ID와 분리된 remote task ID/version을 추가했다.
  모든 write는 Apple Reminders의 exact provider/account/list/task identity, 최신 snapshot과
  authoritative writable-list metadata를 확인한다.
- 행 완료 원을 실제 완료/미완료 버튼으로 바꾸고 per-row progress·중복 입력 방지를 넣었다.
  상단 `+`와 상세 sheet는 list 선택, 제목·전체 notes·기한 설정/제거·완료, Save/Delete/Cancel을
  제공한다. 상세 진입은 최신 원격 snapshot을 다시 읽는다.
- version mismatch는 draft를 보존하고 `Reload Latest`/`Cancel`만 남긴다. read-only, 권한 철회,
  list metadata 실패와 외부 삭제는 write를 차단하고 refresh/설정 복구 메시지를 표시한다.
- 성공 뒤 provider 목록과 linked Event Task projection을 다시 읽는다. 원격 삭제는 local task를
  지우지 않고 missing/Needs attention으로 남긴다. 일반 Reminders notes는 SQLite에 저장하지
  않았고 schema migration도 추가하지 않았다.
- 원격 no-due를 수락한 Event Task가 재연결 때 암묵적 section due 때문에 거짓 conflict가 되던
  비교를 보정해 기존 provider recovery 회귀도 복구했다.
- 검증:
  - focused CRUD/conflict/read-only/revoke/external-delete/local-preservation + 300/360pt render
    **5 tests / 0 failures**
  - `ContextStoreTests` **88 tests / 0 failures**
  - 전체 **268 executed / 267 passed / 1 intentional `ManualEventKitQATests` skip /
    0 failures**, `TEST SUCCEEDED`
  - result bundle:
    `/tmp/KaosCalTasksInteractionBuild/Logs/Test/Test-KaosCal-2026.07.20_12-07-42-+0900.xcresult`
  - unsigned Debug app:
    `/tmp/KaosCalTasksInteractionBuild/Build/Products/Debug/KaosCal.app`
- 결과: **implemented / signed iCloud·On My Mac live fixture pending**.
- 남은 위험: Microsoft To Do mutation, list 이동·capability 확장, Event Brief 연결, calendar
  time blocking과 bulk action은 후속 범위다. 실제 TCC 철회, 동일 이름 계정/list, 외부 동시
  수정 conflict, residue cleanup, keyboard·VoiceOver는 수동 검증해야 한다.

## 2026-07-20 — Tasks 상호작용 2차: 이동·일괄 작업·Undo·원본 열기

- 관련 요구사항: `TASK-006`, `TASK-007`, `PRV-004`, `PRV-009`
- Apple Reminders adapter에 writable destination 검증과 version preflight를 거치는 list move를
  추가했다. 상세 sheet에서 제목·notes·기한·완료 수정과 list move를 한 mutation/Undo 단위로
  처리한다.
- 연결 reminder를 같은 계정 또는 다른 Apple account list로 옮기면 provider item의 account와
  parent, binding version/hash를 한 SQLite transaction에서 옮긴다. 다음 refresh가 이전 parent를
  조회해 local Event Task를 missing으로 오판하지 않는다.
- 명시적 선택 모드와 여러 Apple reminder의 일괄 완료·미완료·list 이동을 추가했다. read-only나
  Microsoft task가 섞이면 bulk write를 시작하지 않는다.
- 생성·수정·완료·이동·삭제와 bulk mutation은 마지막 성공 동작의 process-local Undo를 만든다.
  Undo 직전 모든 after-version을 preflight하며 외부 변경에는 conflict로 멈춘다. 삭제 복원은
  새 remote ID를 생성하고 기존 missing Event Task binding을 새 item에 재연결한다.
- Tasks에 per-mutation Syncing과 마지막 성공 시각, Undo 상태·오류를 표시했다. 행은 focusable하고
  위·아래 방향키로 포커스를 이동하며 Tab/Return/Space의 표준 button 조작을 유지한다.
- Microsoft To Do delta의 신뢰 가능한 Graph deep link는 프로세스 메모리에만 보관해 원본 열기
  버튼에 사용한다. Apple `EKReminder.url`은 사용자 필드라 Reminders deep link로 노출하지 않는다.
- 검증:
  - 새 focused test: 계정 간 move의 binding 보존+Undo, linked delete의 recreate/relink Undo,
    bulk completion composite Undo
  - 전체 **271 executed / 270 passed / 1 intentional `ManualEventKitQATests` skip /
    0 failures**, `TEST SUCCEEDED`
  - result bundle:
    `/tmp/KaosCalTasksInteractionBuild/Logs/Test/Test-KaosCal-2026.07.20_12-32-46-+0900.xcresult`
  - unsigned Debug app:
    `/tmp/KaosCalTasksInteractionBuild/Build/Products/Debug/KaosCal.app`
- 결과: **implemented / live interaction pending**.
- 남은 위험: 실제 iCloud↔On My Mac move·Undo와 residue cleanup, narrow live window의 bulk/Undo
  밀도, keyboard focus·VoiceOver, 외부 변경과 Undo 경쟁은 수동 gate다. offline queue와 durable
  retry/cancel, Microsoft mutation, Calendar 연결·time blocking은 다음 단계다.

## 2026-07-20 — Tasks 통합 관리·planning·Calendar 결합

- 관련 요구사항: `TASK-005`~`TASK-011`, `COM-006`, `COM-011`, `PRV-*`
- 오른쪽 `Tasks`의 공통 mutation route를 Apple Reminders, Google Tasks, Todoist와 Microsoft
  To Do로 확장했다. exact provider/account/list/remote ID와 version을 검증하고 provider
  capability에 따라 notes·완료·due·priority·reminder·원본 URL을 노출한다. Microsoft Graph의
  `isReminderOn`/`reminderDateTime`은 due와 독립적으로 설정·제거한다. Apple 목록·계정 이동과
  Todoist 같은 account의 project/section 이동·일괄 이동을 지원하며 공통 완료·CRUD·process-local
  Undo를 제공한다.
- `v11_local_task_planning`과 `TaskPlanningRepository`를 추가해 local Event/Personal task의
  priority·중요 표시·반복·예상/실제 시간·timer·checklist를 backup/reset과 함께 보존한다.
  반복 완료는 다음 local occurrence를 만들고 checklist와 timer 상태를 안전하게 초기화한다.
- Task Center를 Today/Upcoming/Overdue/No Date/After Review/Completed, 날짜/source grouping,
  role, named local view와 Calendar+Tasks 검색으로 확장했다. Event Brief에 이미 투영된 provider
  task는 중복 표시하지 않는다.
- provider task를 calendar canvas로 drag하면 15분 단위·기본 1시간 event와 During task를
  만들고 exact provider binding을 연결한다. Event Brief의 기존 task 연결, fixed/상대 기한,
  event 이동 뒤 due 재계산, 연결 event 열기·reschedule과 Calendar Set 관련 task filter를
  추가했다.
- 동기화 경계는 두 층으로 유지한다. Event Brief provider write는 v10 durable pending,
  bounded Retry와 cancel-and-local-only를 사용한다. 일반 provider task의 notes는 SQLite에
  복제하지 않으므로 직접 편집 실패는 sheet draft를 보존하고 자동/무한 재시도하지 않는다.
- 최종 감사에서 이동 route와 Undo를 provider capability 기반으로 일반화했다. Apple 계정 간
  목록 이동을 유지하면서 Todoist 공식 move endpoint의 project/section body, exact account
  제한, 연결 Event Task binding 재배치와 Undo를 계약·coordinator 테스트로 고정했다.
- Todoist 완료와 일반 field 편집이 함께 있으면 active task field를 먼저 저장한 뒤 close한다.
  body가 없는 completion 응답 뒤 active/archive를 다시 조회해 최신 완료 상태·version을 반환하고,
  오른쪽 `Completed`에는 최근 90일 completion archive를 포함하되 project/section 중복 identity를
  제거한다.
- 검증:
  - 전체 **280 executed / 279 passed / 1 intentional `ManualEventKitQATests` skip /
    0 failures**, `TEST SUCCEEDED`
  - result bundle:
    `/tmp/KaosCalUnifiedTasksCompleteBuild/Logs/Test/Test-KaosCal-2026.07.20_14-16-19-+0900.xcresult`
  - local ad-hoc Debug app:
    `/tmp/KaosCalUnifiedTasksCompleteBuild/Build/Products/Debug/KaosCal.app`
- 결과: **implemented / four-provider·signed interaction live pending**.
- 남은 위험: 실제 provider 계정 CRUD와 permission revoke, provider별 field round-trip,
  Apple 계정 간 및 Todoist project/section move/Undo, deep link, calendar drag의 provider/EventKit
  부분 성공, residue 0,
  좁은 실창 keyboard·VoiceOver는 수동 검증해야 한다.

## 2026-07-21 — 오른쪽 Tasks 하단 상세 drawer

- 관련 요구사항: `TASK-005`~`TASK-007`
- 오른쪽 Tasks 행 클릭과 `+`가 modal sheet 대신 목록 아래의 resizable `VSplitView` drawer를
  열도록 변경했다. 선택 행을 accent 배경으로 유지하고 다른 작업을 누르면 drawer 안의
  최신 원격 snapshot을 교체한다.
- 기존 provider별 destination·notes·due·reminder·priority·완료·conflict·삭제 흐름은 같은
  editor component로 유지했다. sheet 전용 최소 폭은 Task Center 경로에만 남기고 drawer는
  300~420pt inspector 폭에서 세로 scroll을 사용한다.
- 미저장 상태에서 다른 행이나 닫기를 선택하면 새 modal을 만들지 않고 drawer 내부에서
  `Keep Editing`/`Discard`를 제공한다. 저장 성공 뒤에는 대기 중인 작업으로 이동하며,
  `Esc`, Cancel, 닫기 버튼과 선택 행 재클릭도 같은 close route를 사용한다.
- 검증:
  - unsigned Debug build: `BUILD SUCCEEDED`
  - 기존 sidebar·560pt sheet·새 340×360 drawer offscreen render 3개:
    **3 executed / 3 passed / 0 failures**, `TEST SUCCEEDED`
  - result bundle: `/tmp/KaosCalBottomDrawerRegression.xcresult`
- 결과: **implemented / live resize·keyboard interaction pending**.
- 남은 위험: 실제 300pt inspector에서 여러 provider의 긴 destination 이름, divider resize,
  미저장 draft 전환과 VoiceOver focus는 서명된 앱의 실창 수동 gate로 확인해야 한다.

## 2026-07-21 — Google Tasks Desktop OAuth·date-only due 활성화 기반

- 관련 요구사항: `TASK-005`~`TASK-007`, `PRV-002`~`PRV-009`
- Google Tasks의 포트 없는 `http://127.0.0.1` redirect base는 `NWListener`가 임의 가용 포트를
  확보한 뒤 authorization request를 연다. authorization receipt의 실제 redirect URI를 code
  exchange까지 전달해 두 요청을 일치시켰다. 기존 fixed-port Microsoft/Todoist 설정은 그대로
  유지한다.
- callback의 GET path와 state를 검증하고 한 번만 완료하며 기본 5분 timeout에서 listener와
  Settings의 Connecting 상태를 정리한다. 거부·잘못된 callback·browser open 실패는 재연결 가능한
  오류로 남긴다.
- Google token response의 `openid`와 `https://www.googleapis.com/auth/tasks` 승인 여부를 account
  identity 조회·Keychain 저장 전에 검사한다. 누락 시 credential과 account metadata를 만들지
  않는다. client secret을 받거나 저장하는 경로는 추가하지 않았다.
- `GoogleTaskDueDateCodec`으로 사용자 civil date를 Google의 date-only due 형식에 매핑했다.
  UTC/KST/America/New_York에서 연·월·일을 보존하고, PATCH의 unchanged due는 생략하며 기한
  제거는 JSON `null`로 구분한다. API 거부 시 별도 우회 write는 없다.
- app target에는 public `KAOSCAL_GOOGLE_TASKS_CLIENT_ID` build setting과 포트 없는 redirect
  base를 추가했다. client ID가 비어 있으면 `Not configured`이며 token·remote notes는 기존대로
  SQLite/backup에 저장하지 않는다. Calendar event는 EventKit 경로를 유지한다.
- 문서에는 External/Testing Google Auth Platform 설정, 최소 scope, 7일 refresh-token 만료 가능성,
  production OAuth verification release blocker와 고유 marker/residue 0 live 절차를 추가했다.
- 검증:
  - 동적 loopback timeout **1 test / 0 failures**
  - pagination·중복 callback·scope·HTTP/due 집중 **5 tests / 0 failures**
  - 철회된 refresh token·401 credential cleanup 집중 **2 tests / 0 failures**
  - 권한 철회 뒤 account/binding 재인증 상태와 local task 보존 **1 test / 0 failures**
  - 전체 **292 executed / 291 passed / 1 intentional `ManualEventKitQATests` skip /
    0 failures**, `TEST SUCCEEDED`
  - result bundle:
    `/tmp/KaosCalGooglePlanBaseline/Logs/Test/Test-KaosCal-2026.07.21_18-29-25-+0900.xcresult`
- 결과: **local implementation and automated gate passed / Google live gate pending**.
- 당시 남은 위험: Google Cloud 콘솔의 Tasks API, External/Testing consent, test user와 Desktop
  OAuth client 구성, public client ID 주입 및 실제 Google 계정 live gate.

## 2026-07-23 — Google Tasks 실계정 Cloud 준비

- Google Cloud에서 Tasks API, External/Testing audience, test user와 Desktop OAuth client 구성을
  완료했다.
- 공개 client ID를 Debug/Release `KAOSCAL_GOOGLE_TASKS_CLIENT_ID`에 주입했다. client secret은
  소스·SQLite·backup에 추가하지 않았다.
- Debug build가 성공했고, 생성된 app `Info.plist`에서 client ID 및 포트 없는
  `http://127.0.0.1` redirect base 확장을 확인했다.
- 전체 XCTest는 **292 executed / 291 passed / 1 intentional manual-only skip / 0 failures**로
  통과했다. result bundle은 `/tmp/KaosCalGooglePrePushFinal.xcresult`다.
- clean local ad-hoc Debug app을
  `/tmp/KaosCalGoogleLiveTestApp/Build/Products/Debug/KaosCal.app`에 생성했고 strict code-sign
  검증과 client ID/redirect 확장을 다시 확인했다.
- 결과: **Google Cloud configuration, full automated gate and local test build passed / Google live
  account gate pending**.
- 남은 위험: 실제 Google 계정 연결·CRUD·외부 변경·conflict·재실행/refresh·권한 철회·재연결과
  양쪽 residue 0을 완료해야 한다.

## 2026-07-23 — Google Desktop credential live 교정

- Google consent callback 뒤 token exchange가 `client_secret is missing`으로 거부되는 실계정
  결과를 확인했다. 이는 Microsoft 계정 불일치가 아니라 등록된 Google Desktop OAuth client의
  token endpoint 요구사항이다.
- 루트의 Git-ignored `.env`를 `Config/GoogleOAuth.xcconfig`가 선택적으로 읽어
  `KAOSCAL_GOOGLE_TASKS_CLIENT_SECRET`을 app build에 주입하도록 했다. 개발자/CI가 앱 하나의
  credential을 관리하며 최종 사용자는 secret이나 JSON 파일을 제공하지 않는다.
- authorization code와 refresh-token request에 Google일 때만 form-encoded `client_secret`을
  추가한다. Todoist/Microsoft 흐름은 바꾸지 않았고 사용자 access/refresh token은 계속
  Keychain에만 저장한다.
- client ID, redirect 또는 Google client secret이 비어 있는 build는 Connect를 열지 않고
  `Not configured`으로 표시한다. 설치형 Desktop app의 embedded credential은 추출 가능하며
  서버 비밀로 간주하지 않는다는 경계를 개발 문서에 기록했다.
- 검증: 가짜 로컬 `.env`로 build setting 확장만 확인한 뒤 파일을 즉시 제거했고, token/refresh
  form encoding과 dynamic redirect 교체 뒤 credential 보존 집중 XCTest가 통과했다. 전체 suite도
  **292 executed / 291 passed / 1 intentional manual-only skip / 0 failures**로 통과했다. result
  bundle은 `/tmp/KaosCalGoogleSecretFullTests.xcresult`다. 실제 값은 저장소·로그에 노출하지 않고
  사용자 로컬 `.env`/배포 CI secret으로만 주입한다.
- 실제 Git-ignored `.env` 주입 뒤 clean Debug build와 strict code-sign이 통과했다. app
  `Info.plist`의 client ID, `http://127.0.0.1` redirect, credential의 비어 있지 않음을 원문 출력
  없이 확인했다. live app은
  `/tmp/KaosCalGoogleLiveSecretBuild-20260723/Build/Products/Debug/KaosCal.app`이다.
- 결과: **build injection, request wiring and full automated gate passed / Google live account gate
  pending**.

## 2026-07-23 — Microsoft To Do account identity 정규화·최종 로컬 Release

- Microsoft 연결 중 표시된 `Microsoft returned inconsistent account identity information.`은
  provider 응답 문구가 아니라 KaosCal이 ID token `oid`와 Graph `/me.id`를 Swift 문자열
  완전일치로 비교하며 만든 오류임을 확인했다.
- 두 값은 Microsoft object GUID이므로 `UUID(uuidString:)`로 해석한 값끼리 비교하도록 바꿨다.
  대소문자 표현만 다른 같은 GUID는 연결하고 실제 다른 GUID나 잘못된 GUID는 credential 저장
  전에 계속 거부한다.
- 회귀는 대문자 token `oid`/소문자 Graph `id` 성공과 실제 다른 GUID 실패·credential 미저장을
  각각 검증한다.
- 전체 XCTest는 **293 executed / 292 passed / 1 intentional manual-only skip / 0 failures**로
  통과했다. result bundle은
  `/tmp/KaosCalFinalGate/Logs/Test/Test-KaosCal-2026.07.23_17-51-14-+0900.xcresult`다.
- 최종 로컬 universal Release는
  `/tmp/KaosCalFinalUniversalRelease-20260723/Build/Products/Release/KaosCal.app`에 생성했다.
  CDHash `9d5300b0b2f6195dafeb109231d5448017a00493`, `x86_64`/`arm64`, hardened runtime,
  strict code-sign, sandbox·Calendar·Reminders·파일 선택·network entitlement, OAuth build setting
  주입과 XCTest 비포함 검증을 통과했다.
- 결과: **Microsoft identity false mismatch fixed / full test and local universal ad-hoc Release
  passed / Developer ID notarized public distribution still blocked**.

## 2026-07-24 — Microsoft To Do Graph identity 정본화

- 실제 계정에서 GUID 대소문자 정규화 뒤에도 같은 연결 오류가 재현되어 최초 원인 가설을
  재검토했다. 같은 authorization-code 교환의 ID token `oid`와 Graph `/me.id`를 앱이 다시
  일치 검증하는 것은 To Do API 접근에 필요하지 않았고, 이 앱 내부 검사가 정상 로그인을
  차단하고 있었다.
- Microsoft To Do를 실제로 읽고 쓰는 access token의 Graph `/me.id`를 계정 object identity의
  정본으로 사용한다. ID token에서는 tenant `tid`와 표시 이름 fallback만 읽으며 `oid`는 계정
  키나 상호 검증에 사용하지 않는다.
- tenant와 Graph object ID는 모두 UUID로 검증하고 소문자 표준형으로 저장한다. 회귀는 서로
  다른 token `oid`가 있어도 Graph identity로 연결되는 경로와 잘못된 Graph ID가 credential
  저장 전에 거부되는 경로를 검증한다.
- 전체 XCTest는 **293 executed / 292 passed / 1 intentional manual-only skip / 0 failures**로
  통과했다. result bundle은
  `/tmp/KaosCalMicrosoftGraphIdentityFull/Logs/Test/Test-KaosCal-2026.07.24_09-34-30-+0900.xcresult`다.
- universal ad-hoc Release는
  `/tmp/KaosCalMicrosoftGraphIdentityRelease-20260724/Build/Products/Release/KaosCal.app`에
  생성했다. CDHash `014408484340bed1a501d52b0a0a5d34b2549d1d`, `x86_64`/`arm64`, hardened
  runtime, strict code-sign, sandbox·Calendar·Reminders·파일 선택·network entitlement, XCTest와
  기존 inconsistent-identity 오류 문자열 미포함을 검증했다.
- 결과: **Graph identity-authoritative Microsoft connection fixed / full test and local universal
  ad-hoc Release passed / live account retry pending**.

## 다음 항목 템플릿

```markdown
## YYYY-MM-DD — 작업 제목

- 관련 ADR:
- 변경 파일:
- 검증:
- 결과: pass / fail / blocked
- 남은 위험:
```
