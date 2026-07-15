# Data Model

## 데이터 원칙

원본 일정은 캘린더 계정이 소유한다.
KaosCal은 일정에 붙는 맥락을 로컬 SQLite에 소유한다.

절대 원칙:
- Event Brief 데이터는 `EKEvent.notes`에 쓰지 않는다.
- 원본 일정 삭제와 local context 삭제는 같은 일이 아니다.
- EventKit 식별자는 바뀔 수 있으므로 여러 키와 fingerprint로 복구한다.

## 저장 위치

현재 App Sandbox 빌드(`com.adtstack.kaoscal`):

```text
~/Library/Containers/com.adtstack.kaoscal/Data/Library/Application Support/KaosCal/kaoscal.sqlite
```

샌드박스를 사용하지 않는 내부 진단 빌드에서만:

```text
~/Library/Application Support/KaosCal/kaoscal.sqlite
```

경로는 하드코딩하지 않고 `FileManager.applicationSupportDirectory`에서 계산한다.

## 표시 모델과 영속 모델

Phase 5는 EventKit 객체를 UI 값 snapshot으로 분리하고 필요한 연결·맥락만 SQLite에 영속화했다. Phase 6은 이 경계에 impact preview, recurrence scope, additive change log와 process-session Undo token을 구현했다. Phase 7B는 schema를 바꾸지 않고 occurrence-aware lookup 값, 두 단계 missing 확인과 명시적 recovery 명령을 추가했다. Phase 7C도 기존 v1/v2를 재사용해 linked original delete의 saved-link preview, CAS, `cancelled + orphaned` finalize와 current-link-generation deletion provenance projection을 추가했다. Phase 8은 EventKit snapshot·Event Brief identity와 분리된 role preference만 additive v3에 저장하고, virtual set·typed restriction·duplicate candidate는 파생 projection으로 구현했다. Phase 9은 schema를 추가하지 않고 현재 SQLite 전체의 consistent snapshot과 별도 archive manifest를 만들었다. 이후 v8은 calendar별 표시·가용시간 차단 override를 역할과 분리해 저장한다.

| 값 | 역할 | 영속 모델과의 차이 |
| --- | --- | --- |
| `DisplayEvent` | title, source, calendar color, raw date, read-only, meeting/invitation, availability, canceled/current-user-declined, canonical `isRecurring`, 정규화된 occurrence anchor, representable/unsupported recurrence snapshot, 원본 notes를 UI에 전달 | 앱 재실행 뒤 영속 ID로 사용하지 않음. `originalNotes`는 Event Brief notes가 아님 |
| `CalendarDescriptor` | raw `CalendarSource`와 explicit/inferred role을 결합 | 저장 record가 아니며 `CalendarSource`를 변경하지 않음 |
| `CalendarSetFilter` | `All`과 Work/Personal/Family/Shared/Subscription/Other role별 visible-event filter | process UI state이며 DB에 저장하지 않음 |
| `CalendarUsagePolicy` | calendar별 표시 여부와 가용시간 차단 여부를 explicit/inferred override에서 결합 | 역할·수정 권한과 독립된 local projection이며 원본 event/calendar를 바꾸지 않음 |
| `CalendarWriteRestriction` | invitation, attendee, subscribed, birthdays, provider read-only를 안전한 우선순위로 설명 | EventKit ACL의 숨은 원인을 추측하지 않는 read projection |
| `CalendarDuplicateCandidate` | 다른 calendar의 정규화 title·보수적 시간 범위가 같은 review candidate | 비영속·read-only이며 자동 merge/hide/delete 근거가 아님 |
| `EventTimeSemantics` | `allDay`, `floating`, `zoned` 구분 | `event_links.time_semantics`와 local component snapshot으로 변환 |
| `LocalDateTimeComponents` | 원 calendar identifier와 civil components 보존 | all-day/floating 표시·due·반복 occurrence 재구성에 사용 |
| `DisplayEventIdentity` | SwiftUI selection과 occurrence별 card identity | `external → calendar item → event` 우선순위, local occurrence anchor 사용; 영속 resolver와 목적이 다름 |
| `CalendarEventLayout` | visible period의 timed/all-day placement | 파생값이므로 저장하지 않음 |
| `CalendarEventDraft` | 원본 일정 create/update 입력, recurrence draft와 고정 reference time zone | editor session 동안만 존재하며 DB record가 아님. 저장 시 all-day/floating civil components를 현재 기본 zone에 rebase할 수 있음 |
| `CalendarEventMutationReceipt` | scoped write 결과 event, 실제 write 여부, scope와 changed fields | provider 결과 값이며 EventKit object나 persisted log 자체가 아님 |
| `CalendarEventEditorSession` | new/existing target, writable calendar, local mutation context | AppState의 일시 상태이며 앱 재실행 뒤 복구하지 않음 |
| backup manifest | archive format, app/export metadata, DB schema/migrations, byte count와 SHA-256 | SQLite table이 아닌 ZIP의 `manifest.json`; 기기 이름과 credential을 저장하지 않음 |
| `EventMutationContext` | local Brief 없음/strong linked/확인 필요 구분 | 기존 context를 안전하게 rebind할지 정하는 일시 preflight 결과 |
| `CalendarEventMutationPreview` | original, validated draft, scope, changed fields, mutation context와 local impact를 확인 UI에 전달 | immutable preview 값이며 확인 전에는 EventKit·DB를 바꾸지 않음 |
| `EventMutationImpact` | local notes 유무·글자 수, section별 task count/title, 최근 change history | `ContextStore`의 side-effect-free read projection이며 scope나 EventKit write 권한이 아님 |
| `CalendarEventLookupQuery` / `CalendarEventLookupResult` | 저장 link 또는 최종 선택 event의 strong identifiers, occurrence anchor와 마지막-known snapshot으로 전용 조회 | provider read 값이다. 일반 구간 fetch의 부재나 SQLite 상태 자체가 아님 |
| `LinkedEventRecoverySession` | 첫 missing, recheck, candidate, orphan 확인과 relink 확인을 보관 | AppState의 일시 상태다. expected `EventLink` snapshot은 최종 relink CAS에 사용하지만 별도 DB record는 아님 |
| `LinkedOriginalDeletionPreparation` / `LinkedOriginalDeletionPreview` | active Brief, notes/tasks/history impact, expected `EventLink`와 saved-link change snapshot을 최종 삭제 review에 고정 | 비영속 read 모델이다. final Confirm 전에는 EventKit과 DB를 바꾸지 않으며 expected link/snapshot은 pre-provider 및 post-provider CAS에 사용 |
| `EventBriefSnapshot.hasRecordedOriginalDeletion` / `TaskCenterItem.wasOriginalDeletedByKaosCal` | 현재 link 세대에 유효한 KaosCal deletion provenance를 UI에 전달 | 저장 column이 아니다. unavailable `cancelled` log가 있고 `(created_at, rowid)`상 이후 `relinked`가 없을 때만 true |
| session Undo token | 직전 비반복 `single` write의 change ID와 after snapshot | process 메모리에만 존재. persistent `undo_state`만으로 재실행 뒤 Undo하지 않음 |

영속 Event Brief 연결은 아래 `Identity resolution 순서`로 구현되어 있다. UI ID가 같거나 달라졌다는 사실만으로 local context를 자동 연결·삭제하지 않는다.

`DisplayEvent.isRecurring`은 provider 경계에서 `hasRecurrenceRules || isDetached`로 만든 반복 소속의 canonical 값이다. EventKit은 비반복 이벤트에도 `occurrenceDate == startDate`를 합성할 수 있으므로 raw `occurrenceDate` 존재 여부는 반복 소속을 뜻하지 않는다. provider는 비반복 occurrence anchor를 `nil`로 정규화하며, downstream scope·routing은 `isRecurring`만 사용한다. `occurrenceDate`는 반복으로 판정된 뒤 identity lookup에만 사용한다.

## Historical draft: Schema v0

아래 schema v0는 최초 문서 초안이다. 구현 전 요구사항이 종일·시간대·반복·Task Center로 확장되었으므로, 실제 첫 migration은 다음 v1 baseline을 따른다.

```sql
create table event_contexts (
  id text primary key,
  title_snapshot text not null,
  start_snapshot text,
  end_snapshot text,
  status text not null default 'scheduled',
  notes text,
  created_at text not null,
  updated_at text not null
);

create table event_links (
  id text primary key,
  context_id text not null references event_contexts(id) on delete cascade,
  event_identifier text,
  calendar_item_identifier text,
  calendar_item_external_identifier text,
  calendar_identifier text,
  source_title text,
  calendar_title_snapshot text,
  title_snapshot text,
  start_snapshot text,
  end_snapshot text,
  location_snapshot text,
  fingerprint text not null,
  last_seen_at text,
  link_status text not null default 'active'
);

create table event_tasks (
  id text primary key,
  context_id text not null references event_contexts(id) on delete cascade,
  section text not null,
  title text not null,
  completed integer not null default 0,
  sort_order integer not null,
  due_offset_minutes integer,
  created_at text not null,
  completed_at text
);

create table event_change_log (
  id text primary key,
  context_id text not null references event_contexts(id) on delete cascade,
  change_type text not null,
  before_json text,
  after_json text,
  created_at text not null
);

create table calendar_roles (
  id text primary key,
  calendar_identifier text not null unique,
  role text not null default 'other',
  display_name_override text,
  color_override text,
  visible integer not null default 1,
  created_at text not null,
  updated_at text not null
);

create table event_templates (
  id text primary key,
  name text not null,
  category text,
  tasks_json text not null,
  notes_template text,
  created_at text not null,
  updated_at text not null
);

create table app_settings (
  key text primary key,
  value text not null,
  updated_at text not null
);
```

이 v0의 `calendar_roles` 초안은 실제 Phase 8 schema가 아니다. 구현은 display-name/color/visible을 선행 저장하지 않고 아래 additive `v3_calendar_clarity` 계약을 따른다.

## 구현된 additive schema

첫 GRDB migration `v1_context_store`는 아래 네 테이블만 만든다.

Phase 5 원본 일정 편집은 schema를 바꾸지 않았다. Phase 6은 immutable v1을 유지하고 아래 `v2_event_change_log` additive migration을 적용했다. Phase 7B는 v1 status와 v2 `relinked`, Phase 7C는 v1의 `cancelled`/`orphaned`와 v2 `cancelled`/scope/unavailable Undo를 그대로 사용해 migration을 추가하지 않았다. Phase 8은 기존 table을 수정하지 않고 `v3_calendar_clarity`를 추가했다.

| 테이블 | 현재 책임 |
| --- | --- |
| `event_contexts` | Event Brief title/time snapshot, lifecycle, local notes |
| `event_links` | EventKit identifiers, source/time/recurrence snapshot, identity 후보 |
| `event_tasks` | Before/During/After, ordering, completion, fixed/relative due |
| `personal_tasks` | 독립 개인 할 일, due, ordering, completion |
| `event_change_log` (v2) | linked 원본 변경 history, scope, Undo audit state |
| `calendar_preferences` (v3) | calendar identifier별 명시적 local role override와 source/calendar title snapshot |
| `calendar_usage_preferences` (v8) | calendar identifier별 nullable visibility/blocking override와 source identifier/title snapshot |

모든 `Date` column은 GRDB `.deferredToDate`를 명시해 UTC millisecond TEXT로 저장한다. foreign key를 항상 켜고, context 삭제는 link와 event task 및 v2 change log에 cascade한다. local Brief 삭제는 이 cascade만 사용하며 EventKit event는 건드리지 않는다.

### Event context lifecycle

- `event_contexts.status`는 `lifecycle_status`로 명확히 한다: `scheduled`, `completed`, `cancelled`, `orphaned`.
- `moved`는 현재 상태가 아니라 `event_change_log.change_type = moved`로만 남긴다.
- Event Brief는 일정 선택만으로 만들지 않고, 첫 메모·event task 저장에서 지연 생성한다.
- Phase 7A는 active link의 저장된 유효 종료를 현재 표시 calendar에서 재구성해 `now >= end`이면 `completed`, 아니면 `scheduled`로 reconciliation한다. zoned는 절대 시점, 종일은 배타 종료일, floating은 civil components를 사용한다.
- 자동 시간 전이는 scheduled/completed 사이에서만 일어나고 cancelled/orphaned와 non-active link는 덮어쓰지 않는다. 관찰 파생 완료는 change log가 아니며 일정이 미래로 이동하면 scheduled로 돌아갈 수 있다.
- 일반 EventKit 구간 fetch에서 보이지 않는 사실만으로 missing/orphaned/cancelled를 자동 판정하지 않는다. 첫 사용자 명시 lookup의 `notFound`만 link를 missing으로 만들고, missing 상태의 명시적 Recheck가 다시 `notFound`일 때만 orphan 확인을 연다.
- 전용 lookup이 유일한 canceled EventKit event를 강하게 확인하면 link는 active로 두고 lifecycle을 cancelled로 만든다. 이후 non-cancelled strong `.found`는 cancelled를 해제한 뒤 현재 event end에서 scheduled/completed를 다시 계산한다. 이 provider 관찰은 Phase 7C 원본 삭제가 아니므로 `cancelled` log를 append하지 않는다.

### Phase 7B missing/orphan recovery

- 저장 link query는 event/item/external identifier, calendar, 마지막-known snapshot과 반복 occurrence anchor를 가진다. zoned occurrence는 instant, all-day/floating은 civil components로 비교한다.
- 권한·provider 오류와 candidate/ambiguous/inconclusive 결과는 missing 확인으로 세지 않는다. 어느 calendar에서든 strong identifier seed의 recurrence/occurrence가 저장 anchor와 맞지 않으면 `strongIdentifierOccurrenceMismatch` 또는 `recurringOccurrenceUnavailable`이며 `notFound`가 아니다.
- 첫 `notFound`는 `event_links.link_status`만 active에서 missing으로 바꾸고 `last_seen_at`, context lifecycle, notes/tasks와 마지막-known snapshot을 유지한다. 두 번째 명시적 Recheck의 `notFound`는 UI 확인만 열고 DB를 orphaned로 바꾸지 않는다.
- `Keep as orphan`만 context lifecycle과 link status를 함께 orphaned로 저장한다. orphaned link의 strong-looking live event도 자동 재활성화하지 않고 confirmation candidate로 낮춘다.
- 명시적 Relink는 선택 event의 최종 provider strong verification, strong-ID 존재, 다른 context 충돌 방지와 선택 시점 `EventLink` 전체 equality CAS를 모두 통과해야 한다. snapshot/lifecycle 갱신, 이전 available Undo supersede와 unavailable `relinked` log insert는 한 SQLite transaction이며 실패하면 모두 rollback된다.
- `Delete local Brief`는 missing/orphaned context만 허용한다. context, link, event task, change log를 SQLite cascade로 지우되 `CalendarProviding.deleteEvent`를 호출하지 않는다.

### Phase 7C linked original delete

- preparation은 active Brief와 notes/tasks/history impact를 한 consistent read에서 가져오고 `EventChangeSnapshot(link:)`을 미리 검증한다. 이 saved link와 snapshot이 immutable delete preview의 CAS 기준이다.
- Confirm 직전 `mutationContext`, full expected-link equality와 saved snapshot을 다시 읽어 확인한다. 비반복은 `single`, 반복은 해당 occurrence의 `this_event`만 허용하고 linked `future_events`, attendee/invitation과 read-only 원본은 EventKit 전에 차단한다.
- 성공한 delete receipt 뒤 `finalizeLinkedOriginalDeletion`은 expected link/snapshot을 다시 CAS하고 context lifecycle `cancelled`, link status `orphaned`, 이전 available Undo supersede와 unavailable `cancelled` log insert를 한 SQLite transaction에서 수행한다. `context_id`, notes/tasks, link identifiers/snapshots/fingerprint와 `last_seen_at`은 유지한다.
- deletion log의 before/after는 같은 saved-link snapshot이다. post-delete event가 없고 v1 link는 원본 notes를 저장하지 않으므로 `originalNotes = nil`은 unavailable이며 local notes를 대입하지 않는다. scope는 nonrecurring `single` 또는 recurring `this_event`, undo state는 `unavailable`이다.
- EventKit remove와 local finalize는 원자적이지 않다. receipt가 모순되거나 transaction/CAS가 실패하면 SQLite status/log/Undo supersede는 모두 rollback되지만 원본은 이미 삭제됐거나 삭제됐을 수 있다. UI는 review를 닫고 refresh하며 동일 Delete 재시도를 막고 local Brief 보존을 안내한다. 두 경계 사이 crash도 Phase 7B recovery로 돌아가는 부분 성공이다.
- deleted-original read projection은 상태쌍만으로 만들지 않는다. 해당 context의 unavailable `cancelled` log 중 더 최신 `relinked`가 없는 row가 있어야 하며 순서는 `created_at`, 동일 timestamp에서는 `rowid`로 판정한다. relink 뒤의 current link generation은 과거 cancellation을 상속하지 않는다. 따라서 이후 provider 관찰이나 수동 상태 전이로 다시 `cancelled + orphaned`가 되어도 새 KaosCal deletion log 없이는 일반 orphan이다.
- Phase 7C는 새 status, table, column이나 change type을 요구하지 않으므로 schema migration이 없다.

### Event link temporal and recurrence fields

`event_links`에는 기존 identifier/snapshot 외에 최소 아래 필드를 추가한다.

| 필드 | 목적 |
| --- | --- |
| `is_all_day` | 시간 일정과 날짜 범위를 구분 |
| `time_semantics` | `zoned`, `floating`, `all_day` 구분 |
| `time_zone_identifier` | 고정 시간대 의미 보존, floating은 null |
| `start_local_components`, `end_local_components` | 종일·floating 일정의 안정적인 비교 |
| `recurrence_series_identifier` | 반복 series 후보 연결. EventKit이 master 객체를 보장한다는 의미를 쓰지 않음 |
| `occurrence_date` | 반복 occurrence별 Event Brief 연결과 identity anchor. 이 값의 존재만으로 반복 소속을 판정하지 않음 |
| `occurrence_local_components` | all-day/floating의 원래 civil occurrence 보존 |
| `occurrence_identity_key` | non-recurring, zoned instant, local occurrence를 구분하는 canonical key |
| `is_detached` | 단일 occurrence 예외 여부 |
| `series_fingerprint` | recurrence 후보를 보조 비교 |

식별자+occurrence unique index와 향후 SQL lookup용 index를 migration에서 함께 만든다. Phase 3 resolver는 작은 로컬 link 집합을 한 consistent read로 가져와 Swift에서 우선순위를 판정하며, 동일한 fingerprint만으로 자동 relink하지 않는다.

### Task Center fields

- `event_tasks`에는 `due_kind`, `relative_anchor`, `offset_minutes`, `fixed_due_at`을 둔다. 기존의 모호한 `due_offset_minutes`만으로 일정을 이동시키지 않는다.
- relative offset은 0~2,628,000분으로 제한한다. `at_start`와 `at_end`는 offset 0만 허용한다.
- all-day/floating의 relative due는 저장된 local components를 조회 calendar에서 재구성한다. fixed due는 절대 시점이다.
- `personal_tasks` 테이블을 별도로 둔다. `id`, `title`, `notes`, `due_at`, `completed`, `sort_order`, `created_at`, `updated_at`, `completed_at`을 최소 필드로 사용한다.
- personal task는 EventKit/Exchange에 동기화하지 않는다.

`due_kind = none`인 event task도 Task Center에서 파생 due를 가진다. Before/During은 저장된 event 시작, After는 event 종료를 사용한다. all-day 종료는 배타 범위이므로 After 기본 due가 마지막 표시 날짜의 다음 날이 될 수 있다. 이 값은 notification/reminder가 아니라 목록 분류와 정렬 기준이다.

Phase 4의 `TaskCenterItem`은 저장 record가 아닌 read projection이며 backing identity를 타입으로 유지한다.

```swift
enum TaskCenterItemID {
    case eventTask(taskID: String, contextID: String)
    case personalTask(taskID: String)
}
```

event source projection에는 section, event title, calendar/source, effective event start/end, all-day 여부가 포함된다. UI는 task due와 원본 event range를 구분해 표시한다. 문자열 `event:<id>`/`personal:<id>` parsing은 mutation에 사용하지 않는다.

Personal task due는 생성 뒤 수정하거나 제거할 수 있다. due 없음과 내일 시작 전은 Today, 내일 이후는 Upcoming이다. 완료 task는 due와 무관하게 Completed에 남는다.

### 구현된 V2 event change log

`v2_event_change_log`는 v1 table을 변경하지 않고 아래 record를 추가한다.

| 필드 | 계약 |
| --- | --- |
| `id` | text primary key |
| `context_id` | `event_contexts(id)` foreign key, local context 삭제 시 cascade |
| `change_type` | `created`, `details_updated`, `moved`, `recurrence_changed`, `cancelled`, `completed`, `restored`, `relinked` 중 하나 |
| `scope` | `single`, `this_event`, `future_events` 중 하나 |
| `before_payload`, `after_payload` | non-empty versioned mutation snapshot JSON |
| `undo_state` | `available`, `superseded`, `undone`, `unavailable` 중 하나 |
| `undone_at` | original row가 `undone`일 때만 존재하는 UTC millisecond TEXT Date |
| `undo_of_change_id` | 같은 table의 원본 변경 self foreign key, nullable |
| `created_at` | UTC millisecond TEXT Date 계약 |

`context_id + created_at DESC` 조회 index와 non-null `undo_of_change_id` partial unique index를 둔다. `undo_state = undone`이면 `undone_at`이 필수이고 다른 state에는 없어야 한다. `restored` row만 non-null `undo_of_change_id`와 `unavailable` state를 가지며 self foreign key 삭제는 cascade한다. live EventKit event에서 만든 versioned payload에는 identifiers, calendar/source/title/location/original event notes, raw start/end, all-day/floating civil components 또는 zoned identifier, recurrence occurrence identity를 포함한다. Phase 7B relink의 before와 Phase 7C delete의 before/after는 v1 `event_links`의 마지막-known snapshot으로 만든다. v1 link는 원본 EventKit notes를 저장하지 않았으므로 이 경우 `originalNotes = nil`은 unavailable을 뜻하며 local Event Brief notes로 대체하지 않는다. Phase 7C의 identical before/after에서는 `change_type = cancelled`가 삭제 의미를 전달한다. deleted-original provenance query는 unavailable `cancelled`와 이후 `relinked`의 `(created_at, rowid)` 순서를 사용하며 별도 generation column을 추가하지 않는다. 계정 credential, attendee 목록, Event Brief notes/task 본문은 어떤 payload에도 포함하지 않는다.

linked mutation은 receipt rebind와 log append를 하나의 SQLite transaction으로 수행한다. Phase 7C는 rebind 대신 `cancelled + orphaned`, Undo supersede와 cancellation log를 한 transaction으로 finalize한다. 취소·validation 실패·provider 실패·no-op에는 row를 만들지 않는다. EventKit 성공 뒤 local transaction이 실패하면 false log를 만들거나 다른 context로 자동 연결하지 않는다.

`undo_state = available`은 local repository의 후보 상태일 뿐 UI Undo 권한이 아니다. Undo는 linked calendar/time mutation이 만든 같은 process session의 in-memory token, nonrecurring `single` scope, current event와 logged after snapshot의 exact supported-field match가 모두 있을 때만 시도한다. 같은 context에 새 mutation이 기록되면 이전 available row는 superseded가 되고, 성공한 Undo는 원본을 undone으로 바꾸면서 `restored` row를 atomic append한다.

런타임 provider/scope routing은 canonical `DisplayEvent.isRecurring`만 사용하지만, persisted Undo payload 복원 경로의 recurrence·detached·occurrence 중복 검사는 방어적으로 유지한다. 이는 오래된 record나 모순된 snapshot을 single Undo 후보로 잘못 해석하지 않기 위한 저장 경계 안전장치다.

### 구현된 V3 calendar clarity preference

`v3_calendar_clarity`는 v1/v2 table을 바꾸지 않고 `calendar_preferences`를 추가한다.

| 필드 | 계약 |
| --- | --- |
| `calendar_identifier` | non-empty text primary key. EventKit calendar identifier와 exact match할 때만 override 적용 |
| `source_title_snapshot` | role을 설정할 때의 source title 보조 snapshot |
| `calendar_title_snapshot` | role을 설정할 때의 calendar title 보조 snapshot |
| `role` | `work`, `personal`, `family`, `shared`, `subscription`, `other` CHECK |
| `created_at`, `updated_at` | UTC millisecond TEXT Date 계약 |

`calendar_preferences(role)` index를 둔다. 사용자가 role을 명시적으로 변경할 때만 upsert하므로 단순 calendar/event fetch는 row를 생성하지 않는 sparse 저장소다. subscribed/birthdays의 `Subscription`, 나머지 source의 `Other`는 row가 없을 때 `CalendarRole.inferred`가 만드는 파생값이다.

source/calendar title snapshot은 현재 automatic identifier-churn reconciliation에 사용하지 않는다. 이름이 같다는 이유로 새 calendar identifier에 role을 자동 적용하지 않는다. 현재 source list에 calendar가 없고 exact explicit preference도 없으면 event/task의 account type snapshot으로 역할을 추측하지 않고 `Other`로 표시한다. virtual `CalendarSetFilter`, typed restriction과 duplicate candidate는 모두 비영속 projection이며 v3 row를 만들지 않는다.

### 구현된 V8 calendar usage preference

`v8_calendar_usage`는 역할 row를 바꾸지 않고 `calendar_usage_preferences`를 추가한다.

| 필드 | 계약 |
| --- | --- |
| `calendar_identifier` | non-empty text primary key. EventKit calendar identifier exact match에만 적용 |
| `source_identifier_snapshot` | 설정 당시 EventKit source identifier. account UI grouping과 보조 snapshot이며 자동 rebind 근거가 아님 |
| `source_title_snapshot`, `calendar_title_snapshot` | 설정 당시 표시 이름 보조 snapshot |
| `visibility_override` | nullable boolean. `NULL`이면 기본 visible, 0/1이면 explicit hide/show |
| `blocking_override` | nullable boolean. `NULL`이면 account-type 기본값, 0/1이면 explicit ignore/block |
| `created_at`, `updated_at` | UTC millisecond TEXT Date 계약 |

두 override가 모두 `NULL`인 row는 CHECK로 거부한다. 한 축을 기본값으로 되돌려도 다른
explicit 축은 유지하고, 마지막 override가 제거되면 row를 삭제한다. 단순 calendar/event
fetch는 row를 만들지 않는다. 기본 visibility는 모든 calendar에서 true이고, 기본 blocking은
subscribed/birthdays에서 false, 나머지 account type에서 true다. read-only 상태와 이름은
blocking 기본값을 바꾸지 않는다.

`visibleEvents`는 usage visibility와 현재 virtual role Set을 모두 만족해야 한다. blocking
projection은 raw fetched event에서 별도로 계산한다. calendar blocking이 true여도 EventKit
availability가 free이거나 event가 canceled/current-user-declined이면 제외한다. busy,
tentative, unavailable과 availability 미지원은 포함하고 겹치거나 맞닿은 effective interval을
union한다. 이 projection은 Event Brief observation, identity/relink, duplicate index와 editor
destination을 줄이지 않는다.

duplicate candidate는 fetch 시 `CalendarDuplicateCandidateDetector.candidateIndex`로 한 번 계산해 AppState memory에 event ID별로 보관한다. 카드·Agenda·Inspector는 이 index를 O(1)로 조회하고 DB에 candidate row나 dismissal 상태를 저장하지 않는다. 다음 EventKit refresh에서 index 전체를 새 snapshot으로 교체하고 권한 회수 시 비운다.

## Status values

`event_contexts.lifecycle_status`:
- `scheduled`: 예정된 일정
- `cancelled`: 전용 lookup이 EventKit canceled status를 강하게 확인했거나 Phase 7C linked 원본 삭제가 성공한 일정
- `completed`: 완료 처리된 일정
- `orphaned`: missing 재확인 뒤 사용자가 Keep as orphan을 승인한 context

`event_links.link_status`:
- `active`: 원본 이벤트와 연결됨
- `missing`: 첫 사용자 명시 전용 lookup이 `notFound`였지만 복구 후보와 마지막-known snapshot이 남아 있음
- `orphaned`: missing 재확인 뒤 사용자가 Keep as orphan을 승인했거나 Phase 7C가 원본 삭제 성공 뒤 local Brief를 보관한 상태. lifecycle `cancelled`와 함께인 것만으로 deleted-original은 아니며 current-link-generation unavailable `cancelled` log도 필요하다.

`event_tasks.section`:
- `before`
- `during`
- `after`

`event_change_log.change_type`(v2, Phase 6+):
- `created`
- `details_updated`
- `moved`
- `recurrence_changed`
- `cancelled`
- `completed`
- `restored`
- `relinked`

`event_change_log.scope`:
- `single`
- `this_event`
- `future_events`

`event_change_log.undo_state`:
- `available`
- `superseded`
- `undone`
- `unavailable`

`event_tasks.due_kind`:
- `none`
- `relative`
- `fixed`

## Swift domain model

실제 record는 String ID를 사용하는 `EventContext`, `EventLink`, `EventTask`, `PersonalTask`, `CalendarRolePreference`다. `EventBriefSnapshot`은 context+link+tasks와 current-link-generation deletion provenance 조회 결과이며 별도 테이블이 아니다. `TaskCenterItem`도 event/personal record와 같은 provenance를 합친 파생값이라 저장하지 않는다. lookup query/result, recovery session, virtual set·restriction·duplicate candidate도 비영속 값이다. missing/orphaned는 link/context status로 재구성하지만 deleted-original label은 history ordering까지 요구한다.

첫 non-empty notes 또는 event task가 context와 link를 함께 만든다. 단순 선택과 빈 notes는 row를 만들지 않는다. 첫 저장의 resolve/create와 linked snapshot 갱신은 하나의 write transaction에서 수행한다.

## Identity fingerprint

Fingerprint는 복구 후보를 찾기 위한 보조 키다.
보안용 hash가 아니라 안정적인 비교 키로 취급한다.

입력:
- normalized calendar identifier, title, location
- `zoned`: millisecond absolute start/end
- `all_day`, `floating`: calendar identifier를 포함한 civil start/end components

주의:
- 사용자가 제목이나 시간을 바꾸면 fingerprint가 달라질 수 있다.
- fingerprint 하나만으로 자동 relink하지 않는다.
- 후보가 여러 개면 사용자 확인을 거친다.

## Identity resolution 순서

1. 저장된 `event_identifier`로 직접 lookup
2. 저장된 `calendar_item_identifier`로 lookup
3. `calendar_item_external_identifier`와 `calendar_identifier` 조합으로 후보 검색
4. recurrence series identifier + occurrence identity key + calendar identifier 매칭
5. calendar identifier, time range, title/location snapshot으로 후보 좁히기
6. fingerprint 후보 검색
7. 강한 연결이나 확인 후보가 없으면 `notFound`를 반환한다.

1~4의 강한 연결만 EventKit fetch 관찰 시 title/time/source/identifier/`last_seen_at` snapshot을 자동 갱신한다. missing link가 다시 강하게 관찰되면 active로 복구할 수 있지만 orphaned link는 같은 강한 ID가 보여도 confirmation candidate로 낮춘다. 예외적으로 과거 synthetic occurrence anchor 버그가 recurring으로 저장한 single link는 1~3의 강한 identifier에 더해 calendar/title/location/start/end/time semantics/local components/fingerprint/anchor가 모두 정확히 같을 때만 기존 `context_id`를 유지하며 `single:v1`로 갱신한다. legacy 구조와 strong identifier는 맞지만 snapshot이 다르면 `legacySyntheticSingle` confirmation candidate로 반환하고 자동 갱신하지 않는다. identifier가 없으면 기존 5~6 candidate 정책을 사용한다. 모든 candidate/ambiguous는 사용자 확인 전에는 쓰지 않는다.

반대 방향의 전용 provider lookup은 저장 link에서 query를 만들고 strong identifiers와 occurrence anchor를 함께 검사한다. recurring은 bounded anchor search 안에서 exact zoned instant 또는 civil occurrence를 증명해야 한다. 어느 calendar에서든 strong seed만 보이고 저장 recurrence/occurrence를 증명하지 못하면 inconclusive이며 `notFound`로 상태를 진행하지 않는다. 살아 있는 series의 외부 one-off 삭제와 범위 밖 detached move는 이 read 경계에서 구분할 수 없어 manual exact relink만 제공한다. 반면 Phase 7C가 직접 시작한 `this_event` 삭제는 successful delete receipt가 positive evidence라 exact context를 `cancelled + orphaned`로 finalize할 수 있다. active의 첫 명시적 `notFound`만 missing, missing의 두 번째 명시적 `notFound`만 orphan review를 연다.

## Repository 책임

`AppDatabase`:
- `DatabaseQueue` open과 `v1_context_store`, `v2_event_change_log`, `v3_calendar_clarity` additive migration
- foreign key 활성화
- production Application Support, test in-memory/temporary-file 경계

`EventContextRepository`:
- context/link/brief 조회와 snapshot 갱신 primitive
- context와 link를 함께 가져오는 query
- strong+exact legacy synthetic-single 판정. schema migration 없이 정상 load/observe 시 link snapshot만 single identity로 갱신
- missing/orphan status 전이, recovery Brief 조회, orphan의 자동 재활성화 차단과 relink lifecycle reset primitive
- unavailable `cancelled` 뒤 더 최신 `relinked`가 없는지 `(created_at, rowid)`로 판정해 `EventBriefSnapshot.hasRecordedOriginalDeletion`을 파생

`ContextStore`:
- identity resolution과 첫 context/link 생성의 transaction 경계
- EventKit fetch 관찰 시 강한 link snapshot refresh
- weak candidate의 자동 연결 차단
- lazy Brief load와 context-scoped event task mutation
- side-effect-free navigation target read와 strong-only inverse event match
- typed Task Center completion routing과 missing/context mismatch 방어
- 원본 mutation 전 read-only `EventMutationContext` preflight
- 사용자 승인 뒤 기존 `contextID`의 identifier/snapshot을 갱신하는 transaction rebind. notes/tasks는 유지하고 unique 충돌은 전체 rollback
- `mutationImpact`와 `changeHistory`의 side-effect-free read
- `rebindAndRecordMutation`으로 receipt rebind, 이전 available supersede, 새 log append를 atomic 처리
- `rebindAfterUndo`로 원본 undone, restored append, context rebind를 atomic 처리
- 저장 link lookup target 생성, 첫 missing과 explicit orphan 보관, cancellation/positive recovery 상태 전이
- 최종 provider verification 뒤 expected-link CAS를 통과한 explicit relink의 snapshot/lifecycle/log atomic 처리
- missing/orphaned local Brief의 SQLite-only cascade delete
- linked original delete preparation/validation의 saved-link snapshot, pre-provider CAS와 성공 receipt 뒤 `finalizeLinkedOriginalDeletion`의 status/Undo/log atomic 처리

`EventTaskRepository`:
- task 생성, 수정, 삭제
- section별 ordering
- completion 상태 저장
- Task Center용 due date query

`PersonalTaskRepository`:
- personal task 생성, 수정, 삭제
- 오늘/예정/완료 목록 query

`TaskCenterRepository`:
- event task와 personal task를 한 DB read에서 결합
- typed backing task identity와 event section/effective range, calendar identifier/title/source projection. role은 UI에서 현재 local preference를 합성
- `Today`: 미완료이며 내일 시작 전 due 또는 due 없음. overdue를 포함하되 completed context는 After section만 포함
- `Upcoming`: 미완료이며 내일 시작 이후 due. completed context는 After section만 포함
- `After Review`: completed context의 미완료 After만 포함하고 personal task는 제외
- `Completed`: event/personal 완료 항목을 완료 시각 역순으로 결합
- deleted-original source prefix는 `cancelled + orphaned`와 함께 current-link-generation KaosCal deletion provenance가 있을 때만 표시. 이후 relink는 과거 deletion source를 무효화

`ContextStore.refreshTemporalLifecycle`은 Task Center refresh 전에 같은 DB에서 active context 상태를 갱신한다. `TaskCenterRepository`도 전달받은 `now`와 calendar로 같은 lifecycle을 projection 시점에 계산해, direct read나 clock/time-zone 경계에서도 stale Before/During 작업을 노출하지 않는다. 어떤 경로도 숨긴 작업 row를 삭제하거나 완료 처리하지 않는다.

구현된 Phase 6 change-log 책임(`ContextStore`):
- `mutationImpact(contextID:recentHistoryLimit:)`용 연결 task 수와 최근 history 조회
- `changeHistory(contextID:limit:)` 정렬 조회
- `rebindAndRecordMutation`으로 receipt rebind, 이전 available supersede, 새 log append를 atomic 처리
- `rebindAfterUndo`로 after snapshot 검증 뒤 원본 undone, restored append와 context rebind를 atomic 처리
- 초기 Phase 6에서는 linked future scope를 repository mutation까지 보내지 않음. 후속으로 열 때도 영향 context 전체의 strong reconciliation plan이 provider/use-case preflight에서 성립해야 호출

구현된 `CalendarRoleRepository`(Phase 8):
- calendar identifier별 explicit role preference fetch/upsert/delete/reset/count
- upsert 시 source/calendar title snapshot 갱신, 최초 `created_at` 유지
- EventKit provider write와 분리된 local `AppDatabase` transaction만 사용
- 사용자 표시 이름·색상 override, calendar별 visible 상태와 custom saved set은 현재 repository 범위가 아님

## Migration 원칙

- `v1_context_store`는 Phase 3에서 적용·검증된 immutable baseline이다.
- migration은 한 번 적용되면 수정하지 않는다.
- schema 변경은 새 migration으로 추가한다.
- Phase 6 change log는 `v2_event_change_log`라는 additive migration으로만 추가하며 v1 SQL을 고쳐 쓰지 않는다.
- Phase 7B는 v1/v2의 기존 status, snapshot, foreign key와 `relinked` type만 사용하므로 migration을 추가하지 않는다.
- Phase 7C는 v1의 `cancelled`/`orphaned`, v2의 `cancelled`, 기존 scope와 unavailable Undo를 재사용하므로 migration을 추가하지 않는다.
- Phase 8 role preference는 `v3_calendar_clarity`로만 추가하며 v1/v2 SQL을 고쳐 쓰지 않는다. virtual set·restriction·duplicate projection은 schema를 필요로 하지 않는다.
- Phase 9 archive manifest와 Local Data settings는 schema table이 아니며 migration을 추가하지 않는다.
- destructive migration은 v1에서 금지한다.
- import/reset은 active data를 바꾸기 전에 현재 DB의 자동 recovery backup을 만든다.

## Backup 원칙

Phase 9 export는 Event Brief·task·change log, `calendar_preferences`와 `calendar_usage_preferences`를 포함한 현재 SQLite 전체의 online snapshot과 metadata를 함께 묶는다. 같은 live `DatabaseWriter`에서 snapshot/restore하므로 실행 중 DB 파일이나 WAL sidecar를 직접 복사·교체하지 않는다.

```text
KaosCal-Backup-YYYY-MM-DD-HHmm.zip
├─ kaoscal.sqlite
└─ manifest.json
```

archive는 store-only ZIP이며 root의 위 두 entry만 허용한다. manifest는 최대 64 KiB,
SQLite는 최대 128 MiB, 전체 archive는 최대 129 MiB다. nested path, symlink,
duplicate, extra entry, deflate/encryption/data descriptor/ZIP64/multi-disk,
extra/comment/attribute, trailing/gapped/overlapping payload와 WAL/SHM은 거부한다.

`manifest.json` format v1은 정확한 key 집합을 요구하며 아래 값을 둔다.

- `backup_format_version`
- `application_identifier`, `application_version`, `exported_at`
- `schema_version`, `schema_identifier`, `applied_migrations`
- `database_filename`, `database_byte_count`, `database_sha256`
- `contains_complete_calendar_events = false`
- `contains_linked_event_snapshots = true`, `contains_event_briefs = true`
- `is_encrypted = false`

archive format version은 DB schema와 별도다. 현재 마지막 migration은
`v8_calendar_usage`이며 manifest의 전체 migration 목록과 SQLite 내부 migration table이
맞아야 한다. 기기 이름과 `source_machine_name`은 저장하지 않는다.
SHA-256은 manifest와 DB entry의 byte 일치 확인이며 제작자 서명은 아니다. Phase 9은
실행 중인 앱과 application identifier, current schema object와 migration 목록이
정확히 같은 신뢰 가능한 backup만 허용하고 schema upgrade/downgrade를 하지 않는다.

Import는 archive/manifest/hash/schema/migration을 검사한 뒤 추출 DB의 SQLite integrity와 foreign key를 확인한다. 그 뒤 현재 DB를 `Backups`에 자동 ZIP으로 보존하고 검증된 snapshot을 같은 writer에 restore한다. 사후 schema/integrity/FK도 확인하며 실패 시 pre-operation snapshot rollback을 시도한다. record-level merge는 제공하지 않는다.

Reset은 사전 자동 ZIP 뒤 KaosCal이 소유한 active user-data table을 한 transaction에서 비운다.

- `event_change_log`
- `event_tasks`
- `event_links`
- `event_contexts`
- `personal_tasks`
- `calendar_preferences`
- `calendar_usage_preferences`

reset은 GRDB migration history와 schema를 유지한다. import/reset/export 어느 경로도 EventKit write를 호출하지 않는다.

SQLite에는 linked title/time/location/calendar identifiers와 change payload의 원본
event notes snapshot이 있을 수 있으므로 ZIP은 민감한 plaintext다. KaosCal은 계정
credential, Exchange password/MFA, OAuth token과 attendee 전체 목록을 전용 필드로
수집·저장하지 않고 EventKit 전체 event store도 export하지 않는다. 그러나 사용자
notes/tasks 본문은 검사하거나 redact하지 않으므로 거기에 입력한 민감정보는 그대로
포함될 수 있다. KaosCal은 backup을 자동 암호화·서명하거나 자동 삭제하지 않으며
retention과 신뢰할 수 있는 출처 확인은 사용자 책임이다.

정상 current-schema DB가 열린 Settings 경로만 Phase 9에서 지원한다. failed-bootstrap corrupt live DB recovery는 Phase 10이다. 상세 계약은 [backup-restore.md](backup-restore.md)와 [ADR-015](adr/ADR-015-backup-import-reset-safety.md)를 따른다.
