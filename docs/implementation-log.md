# Implementation Log

이 문서는 실제로 한 작업과 검증 결과를 시간순으로 남긴다. 계획만 적지 않고, 명령·테스트·수동 검증의 성공 또는 실패를 모두 기록한다.

## 기록 규칙

- 코드 또는 사용자에게 보이는 동작을 바꾸면 같은 변경에서 항목을 추가한다.
- 각 항목에는 날짜, 관련 ADR, 변경 파일, 검증, 남은 위험을 적는다.
- 검증하지 못한 내용은 `미검증`으로 명시한다. 추측을 통과로 기록하지 않는다.

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

## 다음 항목 템플릿

```markdown
## YYYY-MM-DD — 작업 제목

- 관련 ADR:
- 변경 파일:
- 검증:
- 결과: pass / fail / blocked
- 남은 위험:
```
