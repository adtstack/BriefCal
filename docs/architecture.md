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
| 일정 제목, 시간, 장소, 참석자, 원본 notes·알림 | Calendar account / EventKit | 사용자의 기존 캘린더 계정 |
| Before/During/After 체크리스트 | KaosCal | Local SQLite |
| KaosCal notes | KaosCal | Local SQLite |
| 변경 기록 | KaosCal | Local SQLite |
| Event Brief 상태 | KaosCal | Local SQLite |
| Personal task | KaosCal | Local SQLite |
| 명시적 캘린더 역할 override | KaosCal | Local SQLite |
| 수동·recovery backup | 사용자 / KaosCal | 사용자가 고른 위치 또는 Application Support `Backups`의 plaintext ZIP |

원칙: KaosCal 고유 데이터는 `EKEvent.notes`에 쓰지 않는다.

## 현재 모듈 구조

아래 tree는 Phase 9 Local Data 구현을 포함한 실제 구조다. recurrence editor와 mutation/linked-delete impact review는 `EventEditorView`, scope·partial-success·session Undo와 missing/orphan/deleted-original recovery 조정은 `AppState`, change-log/relink/delete-finalize transaction은 기존 `ContextStore`에 유지했다. Phase 8은 EventKit snapshot을 바꾸지 않고 `CalendarClarity`의 로컬 projection과 additive v3 preference 저장소를 추가했다. Phase 9은 같은 `AppDatabase` writer의 snapshot/restore와 `ContextStore` local-data service를 Settings UI에 연결하며 새 schema table을 만들지 않는다.

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
│  ├─ CalendarEventLayout.swift
│  ├─ CalendarClarity.swift
│  └─ CalendarEventEditing.swift
├─ ContextStore/
│  ├─ AppDatabase.swift
│  ├─ DatabaseMigrations.swift
│  ├─ ContextModels.swift
│  ├─ ContextStore.swift
│  ├─ EventContextRepository.swift
│  ├─ EventTaskRepository.swift
│  ├─ PersonalTaskRepository.swift
│  ├─ TaskCenterRepository.swift
│  ├─ CalendarRoleRepository.swift
│  ├─ LocalDataBackupService.swift
│  └─ EventIdentityFingerprint.swift
├─ Features/
│  ├─ CalendarShell/
│  │  ├─ CalendarShellView.swift
│  │  └─ CalendarTimelineView.swift
│  ├─ EventBrief/
│  │  └─ EventBriefView.swift
│  ├─ TaskCenter/
│  │  └─ TaskCenterView.swift
│  ├─ EventEditor/
│  │  └─ EventEditorView.swift
│  └─ Settings/
│     └─ LocalDataSettingsView.swift
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
   ├─ CalendarEventEditingTests.swift
   ├─ CalendarClarityTests.swift
   ├─ LocalDataBackupServiceTests.swift
   ├─ AppStateTests.swift
   ├─ LocalWorkspaceTests.swift
   ├─ ManualEventKitQATests.swift
   └─ FakeCalendarProvider.swift
```

`EventBrief`와 `TaskCenter` feature 경계는 Phase 4, `EventEditor`는 Phase 5에서 추가했다. Phase 6과 Phase 7A/7B/7C는 위의 기존 경계를 확장했다. missing/relink와 deleted-original recovery UI도 기존 Calendar shell, Event Brief와 Task Center에 배치했으며 별도 저장 모듈을 만들지 않았다. Phase 8은 `CalendarClarity.swift`에 role·typed restriction·virtual set·duplicate projection을, `CalendarRoleRepository.swift`에 명시적 role override만 두었다. Phase 9의 `LocalDataSettingsView`는 backup/import/reset 확인과 결과 표시만 담당하고 archive validation, automatic backup, hot restore와 reset transaction은 ContextStore 경계에 둔다.

## 런타임 흐름

아래는 Phase 9 구현을 포함한 v1 런타임 흐름이다. 1~8의 기존 일정·local context 흐름에 9의 반복·linked move·change log·session Undo, 10의 missing/orphan recovery, 11의 linked original delete review/finalize, 12의 multi-calendar clarity projection과 13의 local-data maintenance를 구현했다.

1. `KaosCalApp` 초기화가 `AppBootstrap.makeAppState`를 호출한다.
2. production에서는 `AppBootstrap`이 Application Support DB를 열고 migration한 단일 `ContextStore`를 만든다. hosted XCTest에서는 production DB open을 건너뛴다.
3. `AppBootstrap`이 DB 상태와 `ContextStore`를 주입해 `AppState`를 만든다. DB open/migration 실패 시 전역 복구 안내 상태로 시작한다.
4. `CalendarShell`의 시작 task가 `AppState.loadCalendarStatus`를 호출하고 `CalendarProvider`가 EventKit 권한 상태를 확인한다.
5. 권한이 있으면 지정 기간의 이벤트와 캘린더 목록을 가져온다.
6. fetch한 EventKit 값 snapshot을 `ContextStore.observe`가 강한 식별자로 기존 context에 연결하고 최신 snapshot으로 갱신한 뒤 Day/Week/Agenda에 표시한다.
7. 사용자가 체크리스트, notes, 개인 작업, 완료 상태를 바꾸면 SQLite만 변경하고 Event Brief와 Task Center가 함께 갱신된다. local mutation은 AppState 명령을 거쳐 성공 뒤 두 projection을 다시 읽는다.
8. 사용자가 지원되는 일정을 바꾸면 최신 EventKit 원본을 다시 확인하고 변경 필드만 저장한다. 연결된 mutation은 receipt로 기존 context snapshot을 다시 묶고 change log를 같은 local transaction에 append한다.
9. Phase 6의 위험한 변경은 impact preview와 명시적 scope 확인 뒤 EventKit을 쓰고, linked context rebind와 change log를 한 local transaction으로 조정한다. 마지막 linked 비반복 single calendar/time 변경만 process session 안에서 Undo 후보가 된다.
10. 사용자가 linked 원본 열기/Recheck를 요청하면 occurrence-aware provider lookup을 실행한다. 첫 명시적 notFound는 missing, 두 번째 명시적 notFound는 orphan review만 열며 Keep/검증된 Relink/local-only Delete를 서로 다른 명령으로 처리한다.
11. linked 원본 삭제는 saved-link·notes/tasks impact를 고정한 별도 review와 final Confirm을 거친다. 성공한 EventKit receipt 뒤 `cancelled + orphaned`, saved-link unavailable cancellation log와 Undo supersede를 한 SQLite transaction으로 finalize한다. deleted-original projection은 이 current-link-generation provenance까지 확인한다.
12. calendar fetch 후 sparse role preference를 읽어 `CalendarDescriptor`를 만든다. 선택한 role set은 Day/Week/Agenda의 `visibleEvents`만 좁히고, typed restriction과 duplicate candidate는 원본 write 없이 화면·VoiceOver에 projection한다.
13. Settings의 Local Data 명령은 pending local draft와 진행 중 mutation을 먼저 막고 같은 file-backed writer에서 export snapshot을 만든다. import/reset은 현재 DB를 `Backups`에 자동 export한 뒤 검증된 snapshot hot restore 또는 six-table reset transaction을 수행하고 local projection을 다시 읽는다. 이 흐름은 EventKit provider write와 분리된다.

## Phase 4 local interaction pipeline

```text
Calendar selection / Task filter
  → AppState private selection command
  → ContextStore loadBrief or TaskCenterRepository read
  → EventBriefState / TaskCenterState
  → EventBriefView / TaskCenterView

Inline local mutation
  → pending notes flush
  → ContextStore context-scoped transaction
  → selected Brief reload + current Task Center reload
```

- notes debounce task와 현재 draft는 AppState가 소유한다. 같은 event의 EventKit refresh는 active event snapshot만 교체하고 draft를 유지한다.
- task row의 제목 draft는 row가 소유하지만 Return·focus loss·완료·이동·navigation·화면 이탈 전 AppState rename을 먼저 호출한다.
- DB open/migration 실패는 `LocalContextStoreState.failed`로 전체 shell을 차단한다. validation, missing original, weak identity 같은 작업 오류는 `localOperationError`로만 표시해 calendar shell을 중단하지 않는다.
- `TaskCenterItemID`는 backing task ID와 event context ID를 타입으로 보존한다. UI 문자열은 mutation key가 아니다.

원본 일정 navigation과 Phase 7B recovery는 일반 visible-range fetch와 분리된 provider read 경로다.

```text
TaskCenter event source click
  → persisted EventLink → CalendarEventLookupQuery
  → strong identifiers + exact occurrence-aware provider lookup
  → found: snapshot/lifecycle refresh → focused Day + selected event
  → cancelled: active link + cancelled lifecycle → focused event
  → first explicit notFound: link missing only
  → missing + explicit Recheck + notFound: orphan review
  → candidate / ambiguous / error / inconclusive: state unchanged + manual review
```

일반 `fetchEvents(in:)`에서 일정이 보이지 않는 사실은 위 상태 흐름에 들어가지
않는다. 반대로 strong live observation이나 전용 `.found`는 missing link를 active로
복구할 수 있다. orphaned link는 자동 복구하지 않고 explicit Relink 후보로만
노출한다.

## CalendarProvider 경계

```swift
@MainActor
protocol CalendarProviding: AnyObject {
    var authorizationState: CalendarAuthorizationState { get }
    var storeChangeHandler: (() -> Void)? { get set }

    func requestFullAccess() async throws -> Bool
    func listCalendars() throws -> [CalendarSource]
    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent]
    func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) throws -> CalendarEventLookupResult
    func defaultCalendarIdentifierForNewEvents() -> String?
    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent
    func updateEvent(_ original: DisplayEvent, with draft: CalendarEventDraft) throws -> DisplayEvent
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
    func deleteEvent(_ original: DisplayEvent) throws
    func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
}
```

Phase 1은 read-only 경계와 `EventKitProvider` 하나로 시작했고 Phase 5에서 create/update/delete 명령을 확장했다. Phase 6은 scope-aware overload와 write 여부·scope·changed fields를 담는 receipt를 구현했다. Phase 7B는 저장 link와 최종 relink candidate를 확인하는 typed `lookupEvent` read를 추가했다. Phase 7C는 기존 scoped delete receipt를 사용하되 linked Brief의 preparation/CAS/finalize를 AppState와 ContextStore에서 조정한다. Phase 8의 role·set·restriction·duplicate는 provider protocol을 늘리지 않는 local/read-only projection이다. UI는 raw `EKSpan`이나 `EKEvent`를 보관하지 않고 기존 fake/provider 경계를 유지한다. 직접 Google/Microsoft/CalDAV adapter는 만들지 않는다.

Provider는 long-lived `EKEventStore`를 소유하지만 UI에 `EKEvent`를 전달하지 않는다. source, identifier, 시간, 종일, 반복, 초대, 수정 가능 상태를 값 타입 snapshot으로 만든다. 연속 store change 알림은 AppState에서 250ms 병합하고 다시 fetch한다.

반복 소속은 provider 경계에서 아래처럼 한 번 정규화한다. EventKit은 비반복 `EKEvent`도 `startDate` 지정 뒤 `occurrenceDate == startDate`를 반환할 수 있으므로 raw occurrence anchor의 존재 여부를 분류에 사용하지 않는다.

```swift
let isRecurring = event.hasRecurrenceRules || event.isDetached
let occurrenceDate = isRecurring ? event.occurrenceDate : nil
```

이후 UI·scope 요구·single/recurring write routing은 `DisplayEvent.isRecurring`만 canonical 판정으로 사용한다. 정규화된 `occurrenceDate`는 recurring route 안의 lookup·identity reconciliation anchor일 뿐이다. 회귀 테스트는 synthetic `occurrenceDate`가 있는 비반복 `EKEvent`를 single로 유지하고 anchor를 `nil`로 정규화하는 계약을 고정한다.

전용 lookup은 event/item/external identifier 직접 조회와 저장 anchor 주변의 bounded
검색을 합친다. recurring은 같은 identifier만으로 충분하지 않으며 zoned instant
또는 all-day/floating civil occurrence가 정확히 같아야 한다. 어느 calendar에서든
strong seed의 recurrence/occurrence가 저장 anchor와 맞지 않으면
`strongIdentifierOccurrenceMismatch` 또는 `recurringOccurrenceUnavailable`
inconclusive를 반환해 deletion evidence로 세지 않는다. 살아 있는 series에서는
멀리 이동한 detached occurrence와 삭제된 occurrence를 bounded EventKit read로
구분할 수 없으므로 manual exact relink만 제공한다. calendar unavailable, invalid
link, 권한·provider 오류도 같은 보수적 경계를 따른다.

## Phase 7B missing/orphan recovery pipeline

```text
Stored EventLink + user Open Original
  → occurrence-aware dedicated lookup
  → found: active snapshot refresh + scheduled/completed recovery
  → cancelled: active link + cancelled lifecycle
  → first notFound: missing
  → explicit Recheck + second notFound: orphan confirmation
  → Keep as orphan | Select Relink candidate | Delete local Brief

Relink candidate Confirm
  → candidate-based fresh provider query
  → unique strong found/cancelled only
  → expected EventLink equality CAS + target-context collision check
  → one SQLite transaction:
       snapshot/lifecycle rebind
       previous available Undo supersede
       unavailable relinked log append
```

- candidate, ambiguous, notFound, inconclusive와 lookup error는 final Relink 검증을
  실패시키며 SQLite/EventKit을 바꾸지 않는다.
- provider `.cancelled` 관찰은 active link와 local data를 보존하고 lifecycle만
  cancelled로 표시하며 `cancelled` log를 만들지 않는다. 이후 `.found`가 확인되면
  scheduled/completed로 복구한다. 최종 검증된 cancelled Relink는 `relinked` log와
  cancelled lifecycle을 함께 저장한다.
- Relink는 EventKit write가 아니다. provider를 read로 재검증한 뒤 local link만
  다시 묶고 notes/tasks를 보존한다.
- relink before log는 v1 link의 마지막-known snapshot을 사용한다. v1에는 원본
  EventKit notes가 없으므로 `before.originalNotes`는 nil/unavailable이며 KaosCal
  local notes를 절대 대입하지 않는다.
- Delete local Brief는 missing/orphaned context, link, event tasks와 change log를
  foreign-key cascade로 지우지만 EventKit delete를 호출하지 않는다.
- 이 흐름은 기존 v1/v2 schema와 `relinked` change type만 사용해 migration이 없다.

## Phase 7C linked original delete pipeline

```text
Linked editor Delete
  → read-only preparation: Brief + notes/tasks/history impact
  → saved EventLink + EventChangeSnapshot fixed in preview
  → separate final destructive Confirm
  → fresh policy/context check + expected-link/snapshot validation
  → EventKit scoped remove
  → one SQLite transaction:
       expected-link/snapshot equality CAS
       context lifecycle = cancelled
       link status = orphaned
       previous available Undo supersede
       cancelled log with identical saved-link before/after
  → Task Center: Original deleted · Local Brief kept
```

- nonrecurring은 log `single`, recurring occurrence는 `this_event`다. linked
  `futureEvents`, attendee meeting/invitation과 read-only 원본은 provider 호출 전에
  차단한다.
- saved-link payload는 local context가 실제로 연결돼 있던 마지막-known identity와
  time/occurrence snapshot이다. post-delete event가 없으므로 before/after는 같고
  v1 link에 없던 `originalNotes`는 nil/unavailable이다. local notes를 대입하지 않는다.
- `Original deleted`는 status pair의 별칭이 아니다. Brief/Task Center read는
  unavailable `cancelled` log 중 `(created_at, rowid)`상 이후 `relinked`가 없는
  provenance만 현재 link 세대의 삭제로 인정한다. 같은 timestamp에서는 rowid가
  순서를 결정하고, relink 뒤 다시 생긴 외부 `cancelled + orphaned`는 새 KaosCal
  deletion log가 없으면 일반 orphan으로 표시한다.
- EventKit 성공과 local finalize는 원자적이지 않다. receipt 불일치, final CAS/log
  실패나 두 경계 사이 crash는 원본 삭제를 자동 보정하지 않는 부분 성공이다.
  editor/review를 닫아 Delete 재시도를 막고 refresh한 뒤 local Brief가 보존됐음을
  알린다. 실패한 local transaction에는 status/log/Undo supersede가 일부만 남지 않는다.
- Phase 7C는 기존 status, `cancelled` change type, scope와 unavailable Undo를 재사용해
  schema migration이 없다. 비반복 linked original delete는 후속 live gate에서
  EventKit 삭제, Calendar.app/Outlook 부재, local Brief/task 보존을 확인했다.
  반복 `thisEvent`와 retained local Brief cleanup 화면은 session lock으로 미검증이며
  이 제한을 비반복 결과로 대체하지 않는다.

## Phase 5 원본 일정 쓰기 파이프라인(역사적 baseline)

```text
EventEditorView local draft
  → AppState permission / meeting / recurrence / local-identity preflight
  → EventKitProvider strong identifier re-fetch
  → current supported fields == edit-start snapshot
  → writable target + changed-field-only save/remove
  → returned DisplayEvent receipt
  → linked context: ContextStore transaction rebind
  → EventKit refetch + Day focus
```

- `CalendarEventDraft`는 title/calendar/time/all-day/time zone/location/original notes와 편집 시작의 reference time zone을 가진 비영속 값이다.
- 종일 draft는 배타 종료를 사용한다. floating은 nil time zone, zoned는 IANA identifier이며 `Keep local time`은 DST gap/overlap에서 임의 보정하지 않는다. 편집 중 Mac 기본 time zone이 바뀌면 provider validation 전에 reference-zone civil components를 현재 기본 zone에 재구성해 같은 날짜·벽시각으로 저장한다.
- 기존 EventKit 객체는 편집 세션에 보관하지 않는다. 같은 store에서 strong identifier를 순서대로 재조회하고 원 calendar의 유일한 비반복 후보만 쓴다.
- 편집 지원 필드가 외부에서 달라졌으면 stale 오류로 중단한다. zoned는 절대 시점+zone, all-day/floating은 civil components로 비교한다. no-op save는 건너뛰고 실제 변경 필드만 patch해 structured location 등 editor 밖 metadata를 보존한다.
- attendee가 있는 meeting, read-only, recurrence/detached occurrence는 provider와 AppState 양쪽에서 차단한다.
- pending local notes 저장 실패와 weak/ambiguous context는 editor 진입 전에 차단한다. 한 번에 하나의 editor session만 허용한다.
- same-calendar linked update 성공 뒤 `EventMutationContext.linked(contextID)`로 기존 row의 identifier/snapshot만 갱신한다. notes/tasks는 같은 transaction에서 유지되고 unique 충돌은 rollback된다.
- EventKit과 SQLite는 원자적이지 않다. EventKit 성공 뒤 rebind 실패 시 부분 성공을 명시한다. Phase 5 당시 linked calendar 이동은 Phase 6, linked 삭제는 Phase 7C 안전 경계 전까지 provider 호출 전에 차단했다. 현재 linked delete 흐름은 위 Phase 7C pipeline을 따른다.

세부 결정은 [ADR-010](adr/ADR-010-original-event-write-safety.md)을 따른다.

## Phase 6 구현 파이프라인

```text
EventEditor draft + selected occurrence
  → permission / attendee / recurrence-support / local-identity preflight
  → recurrence scope(thisEvent | futureEvents) + affected-context plan
  → immutable impact preview
  → explicit Confirm
  → provider strong re-fetch + fresh snapshot check
  → EventKit scoped save/remove
  → linked context rebind + event_change_log append in one SQLite transaction
  → EventKit refetch + occurrence reconciliation
  → eligible linked nonrecurring single calendar/time write only: in-memory session Undo token
```

- 반복 write, calendar 이동, 기존 시간·종일·time-zone 의미 변경은 confirmation 전에 EventKit write, local rebind, log append가 모두 0회여야 한다. 확인 뒤에도 stale·read-only·attendee 상태를 다시 검사한다.
- `thisEvent`는 선택 occurrence 하나를 대상으로 하며 detached 결과가 생길 수 있다. 복잡한 recurrence도 ordinary fields만 patch하고 recurrenceRules를 보존하는 `thisEvent`는 허용할 수 있다. detached occurrence의 `futureEvents`, 복잡한 rule의 `futureEvents`·rule 변경은 Calendar.app 전용이다.
- 초기 Phase 6은 linked `futureEvents`를 전부 provider 호출 전에 차단한다. 후속으로 열 때도 DB의 영향받는 모든 context를 열거하고 series split 뒤 각각을 강한 identity로 재연결할 계획이 필요하며, 하나라도 weak·ambiguous·missing이면 계속 차단한다.
- linked move 성공 뒤 기존 `contextID`를 유지한다. EventKit 성공과 local transaction 실패는 부분 성공이며 자동 역보정하지 않는다. 이 Phase 6 checkpoint 당시 linked delete는 Phase 7C 전까지 차단했고 현재는 위 별도 Phase 7C review/finalize만 허용한다.
- EventKit save 성공 뒤 identifier churn으로 post-save occurrence receipt를 강하게 확정할 수 없으면 부분 성공으로 처리한다. editor/review를 닫아 동일 변경을 재시도하지 못하게 하고, refresh 후 “Do not retry·Calendar.app에서 확인”을 안내한다. local rebind·log·Undo는 만들지 않고 기존 Event Brief를 보존한다.
- post-write 화면 focus는 refresh 전체 snapshot의 exact display ID를 먼저 사용한다. exact ID가 없을 때 반복 fallback은 strong identity와 같은 calendar에 더해 zoned instant 또는 all-day/floating civil occurrence anchor까지 일치해야 하며, series identifier만 같은 sibling은 선택하지 않는다. 비반복 strong-ID fallback은 유지한다.
- `v2_event_change_log`는 immutable v1 뒤에 추가하는 migration이다. `mutationImpact`, `changeHistory`, mutation rebind+record, undo rebind+record 같은 use-case API가 provider 명령과 local transaction 사이의 경계를 담당한다.
- persistent log의 `undo_state = available`만으로 앱 재실행 뒤 Undo를 허용하지 않는다. UI Undo 권한은 현재 process의 one-shot token, provider의 fresh after-snapshot match, 권한과 strong identity를 모두 요구한다. 일반 EventKit refresh는 자체 save 알림과 외부 알림을 구분할 수 없어 token을 즉시 지우지 않지만, 외부 변경·missing·read-only는 역방향 write 전에 provider stale check로 차단한다. 이후 성공한 KaosCal mutation은 token을 폐기하며 반복 scope, detached, delete는 token을 만들지 않는다.
- `DisplayEvent.isRecurring`이 런타임 scope routing의 단일 기준이어도 persisted Undo snapshot을 복원하는 recurrence·detached·occurrence 중복 검사는 방어적으로 유지한다. 오래된 payload나 불일치 snapshot을 single Undo로 잘못 승격하지 않기 위한 별도 안전장치다.

세부 결정은 [ADR-011](adr/ADR-011-recurrence-move-change-log-and-session-undo.md)을 따른다. 이 파이프라인은 121-test 자동 gate를 통과했지만 실계정 Exchange·`KAOS-TEST` 통과 증거는 아니다.

## Phase 2 표시 파이프라인

```text
EventKitProvider
  → DisplayEvent value snapshot
  → AppState visible period + virtual role-set filter/cache
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
- Phase 8 role set은 EventKit fetch·`ContextStore.observe`·editor destination을 줄이지 않고 렌더링에 쓰는 `visibleEvents`만 필터링한다. set 변경으로 선택 일정이 숨겨지면 pending notes를 먼저 flush하고 selection을 정리한다. duplicate candidate를 열 때는 `All Calendars`로 돌리고 Day에서 정확한 candidate를 선택한다.
- Sidebar의 `MiniMonthGrid`는 Foundation calendar로 month start, first-weekday offset과 42개 civil day만 계산한다. SwiftUI `MiniMonthView`는 월 탐색을 local state로 유지하고 날짜 선택만 `AppState.selectMiniMonthDate`로 보내 기존 selection 정리·range fetch 경계를 재사용한다. 현재 구현은 incomplete fetch를 일정 없음으로 오인하지 않도록 event dot을 만들지 않는다.
- 승인된 `CAL-007`/`UI-005` 확장은 grid의 42일 범위를 완전히 조회하되 기존 loaded interval과 합치거나 별도 cache를 사용해 본문 visible snapshot을 보존한다. 본문 `visibleInterval`에 제한된 `visibleEvents`를 그대로 재사용하지 않고, interval-scoped projection에서 raw event에 `calendar visibility ∩ 선택 Set`을 적용한다. `CalendarEventDateFormatting.effectiveDateRange`의 배타 종료와 표시 calendar의 civil-day overlap으로 `[civil key: count]` index를 셀 렌더링 전에 한 번 계산한 뒤 단일 dot과 접근성 count를 공개한다. 부분 coverage와 오래된 browse 응답에서는 grid 전체 요약을 공개하지 않는다.
- UI용 `DisplayEventIdentity`는 SwiftUI 선택 안정성을 위한 값이다. all-day/floating 반복은 local occurrence anchor를 써 시스템 시간대 변경에도 같은 civil occurrence ID를 유지한다. 영속 resolver와 같은 ID 또는 같은 우선순위를 보장하지 않는다.

세부 배치 결정은 [ADR-007](adr/ADR-007-calendar-layout-and-display-time.md)을 따른다.

## Phase 3 로컬 저장 파이프라인

```text
KaosCalApp / AppBootstrap
  → AppDatabase(DatabaseQueue + v1 + v2 + v3 additive migrations)
  → ContextStore transaction boundary
  → EventContext/EventTask/PersonalTask/CalendarRole repositories
  → TaskCenterRepository combined read
```

- `v1_context_store`는 `event_contexts`, `event_links`, `event_tasks`, `personal_tasks`만 만든 immutable baseline이다. Phase 6은 이 baseline을 바꾸지 않고 `v2_event_change_log`를 additive migration으로 추가했다. Phase 7B는 기존 status/snapshot/foreign key와 v2 `relinked`, Phase 7C는 기존 `cancelled`/`orphaned`, `cancelled` log, scope와 unavailable Undo를 재사용해 migration을 추가하지 않았다. Phase 8은 기존 table을 바꾸지 않고 `v3_calendar_clarity`의 sparse `calendar_preferences`를 추가했다. Phase 9 settings/backup metadata는 DB table이 아니라 archive manifest이며 새 migration을 추가하지 않는다.
- 테스트 host는 `XCTestConfigurationFilePath`를 감지해 default Application Support DB를 열지 않는다. repository test는 in-memory 또는 임시 파일 DB만 사용한다.
- 앱 시작 DB open/migration 실패는 in-memory fallback 없이 전역 복구 화면으로 전환한다. 기존 DB를 삭제하거나 덮어쓰지 않는다.
- 첫 non-empty notes 또는 event task 저장만 context+link를 만들며, resolve부터 insert/update까지 하나의 write transaction이다.
- EventKit fetch 관찰은 강한 ID로 이미 연결된 record만 갱신한다. exact snapshot과 versioned fingerprint는 확인이 필요한 후보다.
- 과거 synthetic `occurrenceDate` 오분류 build가 recurring으로 저장한 실제 single link는 일반 weak relink로 풀지 않는다. 현재 single과 강한 identifier가 맞고 calendar/title/location/time/local-components/fingerprint와 저장 occurrence anchor까지 모두 정확히 같은 경우에만 기존 context를 연결한 뒤 `single:v1` snapshot으로 원자적으로 정상화한다. legacy 구조와 strong identifier는 맞지만 snapshot이 바뀌었으면 자동 연결하지 않고 confirmation candidate로만 노출한다. navigation lookup 자체는 read-only다.
- 반복 identity는 zoned absolute occurrence와 all-day/floating civil occurrence를 분리한다. identifier+occurrence unique index가 동시 중복 생성을 막는다.
- all-day/floating relative task due와 temporal lifecycle은 저장된 local components를 조회 calendar에서 재구성한다. personal task와 event task는 한 consistent read에서 Today/Upcoming/After Review/Completed item으로 합친다.
- 날짜는 UTC millisecond TEXT 계약을 명시한다. details와 선택 근거는 [ADR-008](adr/ADR-008-local-context-store-and-event-identity.md)을 따른다.

## Phase 8 multi-calendar clarity pipeline

```text
CalendarSource + DisplayEvent raw snapshot
  → sparse CalendarRolePreference lookup
  → CalendarDescriptor(role + explicit/inferred)
  → virtual CalendarSetFilter for visibleEvents only
  → role/source: Sidebar / Day / Week / Agenda / Inspector / Task Center / Editor
  → typed restriction: Sidebar / Day / Week / Agenda / Inspector + write preflight
  → duplicate read projection: Day / Week / Agenda / Inspector
```

- `CalendarRole`은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`다. subscribed/birthdays만 `Subscription`으로 추론하고 Exchange·CalDAV·iCloud·local은 이름이나 account type으로 용도를 추측하지 않아 `Other`다.
- 사용자가 role을 바꾼 때만 `CalendarRoleRepository`가 `calendar_preferences`를 upsert한다. 단순 EventKit fetch는 preference row를 만들지 않고, role write는 `CalendarProviding` create/update/delete를 호출하지 않는다.
- `CalendarSetFilter`는 `All`과 role별 virtual filter다. 선택 set은 process UI state이며 v3에 저장하지 않는다. calendar별 visibility는 후속 v8 usage policy에서 구현했고 임의 이름 saved set과 color/name override는 현재 계약이 아니다.
- `CalendarWriteRestriction` 우선순위는 invitation → attendee → subscribed → birthdays → provider-reported read-only다. provider ACL의 구체 사유를 추측하지 않으며 모든 제한 문구는 local Event Brief가 editable임을 함께 밝힌다.
- duplicate detector는 다른 calendar의 정규화 title이 같고, timed start/end가 각각 15분 이내이거나 all-day civil exclusive range가 같을 때만 candidate를 만든다. 같은 strong identity/occurrence는 제외하고 deterministic하게 정렬하며 저장·자동 merge·hide·delete하지 않는다. `AppState`는 fetch snapshot을 받을 때 candidate index를 한 번 계산하고 card/Inspector는 event ID로 O(1) 조회하므로 렌더링 중 전체 event pair를 반복 검사하지 않는다.
- role preference는 exact calendar identifier로만 적용한다. source/calendar title snapshot은 보조 기록이지 identifier churn 후 자동 재연결 근거가 아니다.
- event/task snapshot이 남아 있어도 현재 `calendarSources`에 source가 없고 exact explicit override도 없으면 account type snapshot으로 role을 다시 추론하지 않고 `Other`로 표시한다.

세부 결정은 [ADR-014](adr/ADR-014-multi-calendar-clarity.md)를 따른다. shared read-only Exchange의 실제 typed reason과 긴 source/role 조합의 화면 표시는 fixture·session lock 제한으로 아직 live visual gate를 통과하지 않았다.

## Calendar usage와 availability pipeline

```text
EventKit sourceIdentifier + CalendarSource
  → account별 Settings group
  → sparse CalendarUsagePreference lookup
  → resolved visibility + blocking policy
      ├─ visibleEvents = visible ∩ selected role Set
      └─ blockingEvents = raw events ∩ blocking ∩ event busy state
           → effective interval clamp + overlap union
```

- additive `v8_calendar_usage`는 nullable visibility/blocking override를 역할 preference와
  분리한다. 두 값이 모두 기본값이면 row를 삭제하고 raw fetch만으로 row를 만들지 않는다.
- `CalendarSource.sourceIdentifier`는 source title이 같은 계정을 UI에서 합치지 않기 위한
  grouping identity다. identifier churn 뒤 title만으로 preference를 자동 재연결하지 않는다.
- 모든 calendar는 기본 visible이다. subscribed/birthdays는 기본 non-blocking이고 나머지는
  기본 blocking이다. provider read-only는 non-blocking 근거가 아니다.
- EventKit availability가 free이거나 canceled/current-user-declined인 event는 block하지 않는다.
  tentative와 availability 미지원 event는 MVP에서 block한다. 숨긴 calendar도 blocking에
  참여하며 merged interval은 중복/겹침을 한 번만 나타낸다.
- Settings와 Sidebar 변경은 local repository만 쓰고 `CalendarProviding` mutation을 호출하지
  않는다. raw fetch, Event Brief identity/observation, recovery, duplicate review와 editor
  destination은 usage filter로 줄이지 않는다.

세부 결정은 [ADR-017](adr/ADR-017-calendar-visibility-and-availability.md)을 따른다.

## Phase 9 backup/import/reset pipeline

```text
Settings / AppState local-data operation gate
  → current file-backed ContextStore + pending-notes flush
  → AppDatabase online snapshot on the live DatabaseWriter
  → strict store-only ZIP: kaoscal.sqlite + manifest.json
  → import preflight: archive/manifest/hash/schema/migrations/integrity/FK
  → automatic current-DB ZIP in Application Support/KaosCal/Backups
  → same-writer hot restore or six-table reset transaction
  → post-restore schema/integrity/FK check + local projection reload
```

- archive format version은 SQLite schema와 독립적이다. manifest는 현재 v3까지의 migration 목록, DB byte count와 SHA-256을 기록하며 기기 이름은 기록하지 않는다.
- 수동 파일 작업은 `NSSavePanel`/`NSOpenPanel`에서 사용자가 고른 security-scoped URL과 user-selected read/write entitlement만 사용한다. 자동 backup은 sandbox Application Support 안에 둔다.
- import는 root의 정확한 두 store-only entry만 허용한다. manifest 64 KiB, DB 128 MiB, archive 129 MiB 상한을 두고 filesystem file replacement, WAL/SHM copy, nested path, duplicate/symlink/extra entry, deflate/encryption/data-descriptor/ZIP64/multi-disk와 record-level merge는 사용하지 않는다.
- SHA-256은 archive 내부 byte integrity 검사일 뿐 제작자 서명이 아니다. 실행 중인 앱과 application identifier·current schema object·migration 목록이 정확히 같은 신뢰 가능한 KaosCal backup만 import하며 과거 schema 자동 migration이나 미래 schema downgrade는 하지 않는다.
- import/reset은 automatic backup이 성공해야 active data를 바꾼다. restore 사후 검증이 실패하면 같은 writer에 pre-operation snapshot rollback을 시도한다.
- reset은 여섯 user-data table row만 한 transaction에서 비우고 GRDB migration history와 schema를 유지한다.
- ZIP은 plaintext이고 linked title/time/location/identifier, original-notes change snapshot을 포함할 수 있다. KaosCal은 계정 credential/token을 전용 필드로 수집하지 않고 EventKit 전체 event store도 export하지 않지만, 사용자 notes/tasks 본문은 검사·redact하지 않으므로 그 안에 입력한 민감정보는 그대로 포함될 수 있다.
- 자동 backup은 retention/pruning 없이 `Backups`에 보존한다. 사용자가 직접 관리한다.
- 정상 store가 열려야 Phase 9 Settings operation을 시작할 수 있다. Phase 10의 별도
  bootstrap coordinator는 store open 실패 상태에서만 strict backup을 preflight하고,
  live SQLite 파일군을 `Recovery`로 격리한 뒤 replacement를 재오픈한다. 성공하면 새
  `AppState`로 shell을 교체하고, 실패하면 원본 파일군 rollback을 시도한다.

archive와 privacy 계약은 [backup-restore.md](backup-restore.md), 결정 근거는 [ADR-015](adr/ADR-015-backup-import-reset-safety.md)를 따른다.

## Event Brief 경계

Event Brief는 EventKit 이벤트의 부속 UI처럼 보이지만 저장과 생명주기는 KaosCal이 관리한다. Phase 4는 지연 생성, notes autosave, task CRUD·완료와 Task Center projection을 구현했다. Phase 5는 same-calendar 비반복 원본 수정 뒤 explicit rebind를 추가했고, Phase 6은 linked move·반복 occurrence reconciliation·change log를 구현했다. Phase 7A는 종료 시각 기반 scheduled/completed와 After Review를, Phase 7B는 missing/orphan review·검증된 relink·local-only delete를 구현했다. Phase 7C는 final review 뒤 linked original delete와 local Brief 보존 finalize를 구현했다.

- Event Brief 생성: 이벤트를 단순 선택할 때는 만들지 않고, 사용자가 처음 메모나 작업을 저장할 때 local context를 만든다.
- Event Brief 수정: SQLite에만 쓴다.
- same-calendar 시간 의미 변경: linked 일정은 before/after impact confirmation 뒤 context rebind·change log를 한 local transaction으로 수행한다.
- calendar 간 이동: linked nonrecurring single과 안전한 `thisEvent`는 strong preflight·impact confirmation·receipt rebind를 통과하면 기존 context를 유지한 채 이동한다. linked `futureEvents`는 계속 사전 차단한다.
- 반복 future 변경: 영향받는 local context 전체를 안전하게 reconciliation할 수 없으면 차단한다.
- 시간 lifecycle: active occurrence의 유효 종료가 현재 시각 이하이면 completed다. 종일 배타 종료와 floating civil time을 사용하고 cancelled/orphaned는 시간 계산으로 덮어쓰지 않는다. Today/Upcoming은 완료 일정의 After만 투영하며 Before/During row 자체는 보존한다.
- 원본 부재 확인: 일반 범위 조회의 한 번 부재는 삭제로 판정하지 않는다. 전용 strong occurrence lookup의 첫 명시적 notFound와 missing Recheck의 두 번째 notFound만 recovery 흐름을 진행한다.
- local Brief 삭제: missing/orphaned context만 SQLite cascade로 삭제하며 EventKit 원본은 유지한다.
- 원본 일정 삭제: active linked event는 notes/tasks/history impact review와 별도 final Confirm 뒤에만 원본을 지운다. 성공하면 local Brief는 `cancelled + orphaned`와 unavailable cancellation provenance로 남는다. Task Center는 현재 link 세대 provenance가 있을 때만 deleted-original 상태로 다시 연다. linked `futureEvents`와 attendee/invitation 원본은 계속 차단한다.

세부 lifecycle·missing 확인 경계는 [ADR-012](adr/ADR-012-lifecycle-after-review-and-orphan-confirmation.md)를 따른다.

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

1~4만 strong match로 자동 연결하고 관찰 snapshot을 갱신한다. missing은 strong positive observation으로 active 복구할 수 있지만 orphaned는 strong-looking match도 confirmation candidate로 낮춰 explicit Relink를 요구한다. 단, legacy synthetic-single 호환 경로는 1~3의 강한 identifier 필터 안에서 전체 snapshot과 anchor가 정확히 같은 경우에만 recurring 저장값을 single로 정상화한다. legacy 구조와 1~3 strong identifier는 맞지만 snapshot이 달라졌으면 별도 confirmation candidate로 반환하고 자동 갱신하지 않는다. 5~6도 candidate/ambiguous이며 자동 relink하지 않는다.

저장 link에서 EventKit으로 향하는 전용 lookup은 별도다. strong identifier와 exact occurrence를 함께 요구하고, 첫 명시적 notFound만 missing으로 저장한다. 두 번째 명시적 Recheck notFound는 orphan review만 열며 candidate/ambiguous/error/inconclusive는 상태를 바꾸지 않는다.

## 권한과 read-only 상태

앱은 권한 상태를 제품 경험의 일부로 다룬다. macOS 14 이상에서는 이벤트 목록을 읽기 위해 full calendar access를 명시적으로 요청한다.
권한이 없으면 빈 화면이 아니라 복구 경로를 보여준다.
읽기 전용 캘린더의 이벤트는 Event Brief 편집은 가능하지만 원본 일정 수정 UI는 비활성화한다.

Phase 8은 원본 수정 불가 사유를 typed projection으로 통일한다. invitation·attendee는 Calendar.app 관리 정책, subscribed·birthdays는 해당 source 특성, 나머지 read-only는 “macOS Calendar가 read-only로 보고함”까지만 설명한다. `AppState.validateOriginalWritePolicy`도 같은 `CalendarWriteRestriction`을 직접 throw하여 Inspector 설명과 write preflight의 이유·우선순위가 다르지 않다. provider는 Confirm 후 fresh EventKit 권한을 다시 검사한다. Exchange 공유 ACL의 구체 원인은 EventKit이 제공하지 않는 한 추측하지 않는다. shared read-only Exchange fixture 실계정 gate는 아직 미검증이다.

## 오류 처리 원칙

- EventKit 실패는 사용자가 이해할 수 있는 캘린더/권한/네트워크/계정 상태 문구로 바꾼다.
- 정상 store에서 export/import/reset 실패는 active DB를 유지하거나 사전 snapshot으로 rollback하고 EventKit을 건드리지 않는다. SQLite open/migration 실패는 일반 shell 대신 bootstrap recovery를 표시한다. backup 전체 사전검사 전에는 기존 파일을 건드리지 않고, 이후에는 SQLite 파일군을 함께 격리하며 replacement 재오픈 실패 시 원본 rollback을 시도한다.
- EventKit 변경과 SQLite rebind/change log는 한 use case에서 조정하되 같은 transaction이라고 가정하지 않는다. rebind 또는 Phase 7C status finalize와 log append끼리는 하나의 SQLite transaction으로 묶고, EventKit만 성공하면 실제 성공 범위·local data 보존·log 미기록 상태를 명시한다. linked delete 부분 성공은 같은 Delete를 재시도하지 않는다.
- 일정 삭제와 local context 삭제는 별도 명령으로 분리한다. Phase 7B local delete는 EventKit을 호출하지 않고, Phase 7C linked original delete는 local context를 cascade 삭제하지 않는다.

## 열어둘 결정

- 배포 전 최종 bundle identifier와 signing team
- Mac App Store 배포 여부
- AppKit 보강 범위
- 라이선스 공급자
