# Architecture

## 아키텍처 목표

KaosCal은 macOS 14 이상을 대상으로 하는 macOS-first local-first calendar다.
원본 캘린더 이벤트는 사용자의 캘린더 계정이 소유하고, KaosCal은 그 이벤트에 붙는 맥락을 로컬 데이터베이스에 저장한다.

핵심 목표는 세 가지다.

1. macOS Calendar와 자연스럽게 연결된다.
2. Event Brief 데이터가 원본 calendar notes를 오염시키지 않는다.
3. EventKit 식별자가 변해도 가능한 한 Event Brief를 복구한다.

## 기술 선택

| 영역 | 선택 | 이유 |
| --- | --- | --- |
| App | SwiftUI macOS app | Mac 네이티브 UX와 빠른 v1 구현 |
| Calendar access | EventKit | macOS Calendar/Internet Accounts에 연결된 계정을 활용 |
| Local DB | SQLite + GRDB.swift | 구조화된 local-first 저장, migration, 테스트 용이성 |
| State | Observable models / ViewModels | 초기 복잡도를 낮추고 SwiftUI와 자연스럽게 연결 |
| Task Center | Local event tasks + personal tasks | 일정 맥락과 오늘 할 일을 한 흐름에서 확인 |
| Distribution | Direct download first | 서버 없는 one-time license 모델과 잘 맞음 |
| Sync | No custom sync in v1 | 직접 Google/Microsoft/CalDAV sync는 v2 이후 검토 |

빌드 기준은 [ADR-006](adr/ADR-006-native-project-build-baseline.md)을 따른다. 현재 provisional bundle identifier는 `com.adtstack.kaoscal`이다.

## 데이터 소유권

| 데이터 | 소유자 | 저장 위치 |
| --- | --- | --- |
| 일정 제목, 시간, 장소, 참석자, 원본 알림 | Calendar account / EventKit | 사용자의 기존 캘린더 계정 |
| Before/During/After 체크리스트 | KaosCal | Local SQLite |
| KaosCal notes | KaosCal | Local SQLite |
| 변경 기록 | KaosCal | Local SQLite |
| Event Brief 상태 | KaosCal | Local SQLite |
| Personal task | KaosCal | Local SQLite |
| 캘린더 역할과 표시 설정 | KaosCal | Local SQLite |

원칙: KaosCal 고유 데이터는 `EKEvent.notes`에 쓰지 않는다.

## 현재 모듈 구조

아래 tree는 Phase 3 완료 시점에 저장소에 실제로 존재하는 구조다.

```text
KaosCal.app
├─ App/
│  ├─ KaosCalApp.swift
│  └─ AppState.swift
├─ CalendarKit/
│  ├─ CalendarProvider.swift
│  ├─ EventKitProvider.swift
│  ├─ CalendarModels.swift
│  ├─ CalendarEventDateFormatting.swift
│  └─ CalendarEventLayout.swift
├─ ContextStore/
│  ├─ AppDatabase.swift
│  ├─ DatabaseMigrations.swift
│  ├─ ContextModels.swift
│  ├─ ContextStore.swift
│  ├─ EventContextRepository.swift
│  ├─ EventTaskRepository.swift
│  ├─ PersonalTaskRepository.swift
│  ├─ TaskCenterRepository.swift
│  └─ EventIdentityFingerprint.swift
├─ Features/
│  └─ CalendarShell/
│     ├─ CalendarShellView.swift
│     └─ CalendarTimelineView.swift
├─ DesignSystem/
│  └─ KaosCalTheme.swift
├─ Resources/
│  ├─ Assets.xcassets
│  ├─ Info.plist
│  └─ KaosCal.entitlements
└─ KaosCalTests/
   ├─ ContextStoreTests.swift
   ├─ CalendarEventLayoutTests.swift
   ├─ CalendarAccessTests.swift
   ├─ AppStateTests.swift
   └─ FakeCalendarProvider.swift
```

`EventBrief`, `TaskCenter`, `MoveConfirmation`, `AfterReview`, `Settings`의 별도 feature 경계는 해당 phase에서 실제 파일을 추가할 때 확정한다. Phase 3에서는 Event Brief와 Task Center의 저장소·query만 `ContextStore`에 있고 실제 편집 화면은 없다.

## 런타임 흐름

아래는 v1 런타임 흐름이다. Phase 3까지 1~6의 저장·관찰 기반과 CalendarShell의 Day/Week/Agenda 읽기·표시를 구현했다. 7의 실제 편집 UI는 Phase 4, 8의 일정 쓰기와 change log는 Phase 5~6 범위다.

1. `KaosCalApp` 초기화가 `AppBootstrap.makeAppState`를 호출한다.
2. production에서는 `AppBootstrap`이 Application Support DB를 열고 migration한 단일 `ContextStore`를 만든다. hosted XCTest에서는 production DB open을 건너뛴다.
3. `AppBootstrap`이 DB 상태와 `ContextStore`를 주입해 `AppState`를 만든다. DB open/migration 실패 시 전역 복구 안내 상태로 시작한다.
4. `CalendarShell`의 시작 task가 `AppState.loadCalendarStatus`를 호출하고 `CalendarProvider`가 EventKit 권한 상태를 확인한다.
5. 권한이 있으면 지정 기간의 이벤트와 캘린더 목록을 가져온다.
6. fetch한 EventKit 값 snapshot을 `ContextStore.observe`가 강한 식별자로 기존 context에 연결하고 최신 snapshot으로 갱신한 뒤 Day/Week/Agenda에 표시한다.
7. Phase 4에서는 사용자가 체크리스트, notes, 개인 작업, 완료 상태를 바꾸면 SQLite만 변경하고 Event Brief와 Task Center가 함께 갱신된다.
8. Phase 5~6에서는 사용자가 일정 자체를 바꾸면 EventKit을 변경하고, 확정된 변경 뒤 change log를 SQLite에 남긴다.

## CalendarProvider 경계

```swift
@MainActor
protocol CalendarProviding: AnyObject {
    var authorizationState: CalendarAuthorizationState { get }
    var storeChangeHandler: (() -> Void)? { get set }

    func requestFullAccess() async throws -> Bool
    func listCalendars() throws -> [CalendarSource]
    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent]
}
```

Phase 1은 위 read-only 경계와 `EventKitProvider` 하나로 시작한다. Phase 5에서 create/update/delete 명령을 별도 안전 use case로 확장한다. 직접 Google/Microsoft/CalDAV adapter는 만들지 않는다.

Provider는 long-lived `EKEventStore`를 소유하지만 UI에 `EKEvent`를 전달하지 않는다. source, identifier, 시간, 종일, 반복, 초대, 수정 가능 상태를 값 타입 snapshot으로 만든다. 연속 store change 알림은 AppState에서 250ms 병합하고 다시 fetch한다.

## Phase 2 표시 파이프라인

```text
EventKitProvider
  → DisplayEvent value snapshot
  → AppState visible period/filter/cache
  → CalendarEventLayout
  → CalendarTimelineView / AgendaView / EventInspectorView
```

- `DisplayEvent`는 EventKit 객체가 아니라 calendar color, source, read-only, recurrence, 시간 의미를 가진 값 snapshot이다.
- all-day와 floating은 `LocalDateTimeComponents`에 원래 calendar identifier를 함께 보존하고 표시 calendar의 time zone에서 재구성한다. zoned는 raw `Date`의 절대 시점을 사용한다.
- EventKit all-day raw end가 다음 날 자정 또는 마지막 날 `23:59:59`로 들어오는 두 경우를 provider 경계에서 배타 종료 자정으로 정규화한다.
- `AppState`는 Day 1일, Week/Agenda 7일의 같은 visible interval을 사용한다. 실행 시 오늘 -30/+90일을 읽고 화면이 범위를 벗어나면 visible interval 앞 30일·뒤 90일을 포함해 다시 읽는다.
- pending 범위 조회는 다음 navigation 전에 취소해 오래된 결과가 현재 화면을 덮지 않게 한다. `EKEventStoreChanged`는 마지막 loaded interval을 250ms 병합 재조회한다.
- `CalendarEventLayout`은 Foundation-only 계산이다. 현지 자정 분할, all-day span/row, wall-clock minute, 최소 visual interval, overlap column만 만들고 SwiftUI 좌표는 보관하지 않는다.
- `CalendarTimelineView`는 24시간 축, 고정 header/all-day lane, 현재 시각선, timed/all-day `Button` card를 렌더링한다. 고밀도 timed 일정은 날짜 너비를 늘려 가로 scroll하고, 종일 lane은 높이를 제한해 내부 세로 scroll한다.
- UI용 `DisplayEventIdentity`는 SwiftUI 선택 안정성을 위한 값이다. all-day/floating 반복은 local occurrence anchor를 써 시스템 시간대 변경에도 같은 civil occurrence ID를 유지한다. 영속 resolver와 같은 ID 또는 같은 우선순위를 보장하지 않는다.

세부 배치 결정은 [ADR-007](adr/ADR-007-calendar-layout-and-display-time.md)을 따른다.

## Phase 3 로컬 저장 파이프라인

```text
KaosCalApp / AppBootstrap
  → AppDatabase(DatabaseQueue + v1 migration)
  → ContextStore transaction boundary
  → EventContext/EventTask/PersonalTask repositories
  → TaskCenterRepository combined read
```

- `v1_context_store`는 `event_contexts`, `event_links`, `event_tasks`, `personal_tasks`만 만든다. change log, calendar role, settings는 후속 additive migration이다.
- 테스트 host는 `XCTestConfigurationFilePath`를 감지해 default Application Support DB를 열지 않는다. repository test는 in-memory 또는 임시 파일 DB만 사용한다.
- 앱 시작 DB open/migration 실패는 in-memory fallback 없이 전역 복구 화면으로 전환한다. 기존 DB를 삭제하거나 덮어쓰지 않는다.
- 첫 non-empty notes 또는 event task 저장만 context+link를 만들며, resolve부터 insert/update까지 하나의 write transaction이다.
- EventKit fetch 관찰은 강한 ID로 이미 연결된 record만 갱신한다. exact snapshot과 versioned fingerprint는 확인이 필요한 후보다.
- 반복 identity는 zoned absolute occurrence와 all-day/floating civil occurrence를 분리한다. identifier+occurrence unique index가 동시 중복 생성을 막는다.
- all-day/floating relative task due는 저장된 local components를 조회 calendar에서 재구성한다. personal task와 event task는 한 consistent read에서 Today/Upcoming/Completed item으로 합친다.
- 날짜는 UTC millisecond TEXT 계약을 명시한다. details와 선택 근거는 [ADR-008](adr/ADR-008-local-context-store-and-event-identity.md)을 따른다.

## Event Brief 경계

Event Brief는 EventKit 이벤트의 부속 UI처럼 보이지만 저장과 생명주기는 KaosCal이 관리한다. 아래는 v1 목표 정책이며, Phase 3은 지연 생성·SQLite 수정 primitive와 조회만 구현했다. 실제 편집 UI는 Phase 4, move/change log와 orphan lifecycle은 Phase 6~7 범위다.

- Event Brief 생성: 이벤트를 단순 선택할 때는 만들지 않고, 사용자가 처음 메모나 작업을 저장할 때 local context를 만든다.
- Event Brief 수정: SQLite에만 쓴다.
- 일정 이동: EventKit 변경 전 확인하고, 확인 후 change log를 남긴다.
- 원본 일정 삭제: local context를 즉시 삭제하지 않고 orphaned 상태로 전환한다.

## Identity resolution

EventKit의 eventIdentifier는 영구 절대값으로 취급하지 않는다. 특히 반복 일정은 occurrence별 정보와 detached 상태를 따로 보존한다.
연결 복구는 아래 순서로 시도한다.

1. `eventIdentifier` 직접 매칭
2. `calendarItemIdentifier` 매칭
3. `calendarItemExternalIdentifier` + calendar identifier 매칭
4. recurrence series + occurrence identity key + calendar identifier 매칭
5. calendar identifier + 시간 범위 + title/location snapshot 매칭
6. title/start/end/location 기반 fingerprint 후보
7. 실패 시 `notFound`로 유지

1~4만 strong match로 자동 연결하고 관찰 snapshot을 갱신한다. 5~6은 candidate/ambiguous이며 자동 relink하지 않는다. `missing`/`orphaned` 상태 전환과 사용자 relink UI는 Phase 6~7 범위다.

## 권한과 read-only 상태

앱은 권한 상태를 제품 경험의 일부로 다룬다. macOS 14 이상에서는 이벤트 목록을 읽기 위해 full calendar access를 명시적으로 요청한다.
권한이 없으면 빈 화면이 아니라 복구 경로를 보여준다.
읽기 전용 캘린더의 이벤트는 Event Brief 편집은 가능하지만 원본 일정 수정 UI는 비활성화한다.

## 오류 처리 원칙

- EventKit 실패는 사용자가 이해할 수 있는 캘린더/권한/네트워크/계정 상태 문구로 바꾼다.
- SQLite open/migration 실패는 데이터 손실 없이 앱 화면을 중단하고 기존 파일 보존·백업/복구 안내를 제공한다. 실제 export/import 복구 도구는 Phase 9 범위다.
- EventKit 변경과 SQLite change log 기록은 하나의 use case로 관리하고, 한쪽만 성공했을 때 재시도·보정·사용자 안내를 남긴다.
- 일정 삭제와 local context 삭제는 별도 명령으로 분리한다.

## 열어둘 결정

- 배포 전 최종 bundle identifier와 signing team
- Mac App Store 배포 여부
- AppKit 보강 범위
- 라이선스 공급자
