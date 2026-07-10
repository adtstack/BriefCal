# Data Model

## 데이터 원칙

원본 일정은 캘린더 계정이 소유한다.
KaosCal은 일정에 붙는 맥락을 로컬 SQLite에 소유한다.

절대 원칙:
- Event Brief 데이터는 `EKEvent.notes`에 쓰지 않는다.
- 원본 일정 삭제와 local context 삭제는 같은 일이 아니다.
- EventKit 식별자는 바뀔 수 있으므로 여러 키와 fingerprint로 복구한다.

## 저장 위치

직접 배포 빌드:

```text
~/Library/Application Support/KaosCal/kaoscal.sqlite
```

Mac App Store sandbox 빌드:

```text
~/Library/Containers/com.yourcompany.KaosCal/Data/Library/Application Support/KaosCal/kaoscal.sqlite
```

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

## V1 baseline to implement

첫 GRDB migration은 아래 요구사항을 반영한다. 아직 실행된 DB가 없으므로 schema v0를 그대로 구현하지 않는다.

### Event context lifecycle

- `event_contexts.status`는 `lifecycle_status`로 명확히 한다: `scheduled`, `completed`, `cancelled`, `orphaned`.
- `moved`는 현재 상태가 아니라 `event_change_log.change_type = moved`로만 남긴다.
- Event Brief는 일정 선택만으로 만들지 않고, 첫 메모·event task 저장에서 지연 생성한다.

### Event link temporal and recurrence fields

`event_links`에는 기존 identifier/snapshot 외에 최소 아래 필드를 추가한다.

| 필드 | 목적 |
| --- | --- |
| `is_all_day` | 시간 일정과 날짜 범위를 구분 |
| `time_semantics` | `zoned`, `floating`, `all_day` 구분 |
| `time_zone_identifier` | 고정 시간대 의미 보존, floating은 null |
| `start_local_components`, `end_local_components` | 종일·floating 일정의 안정적인 비교 |
| `recurrence_master_identifier` | 반복 series 후보 연결 |
| `occurrence_date` | occurrence별 Event Brief 연결 |
| `is_detached` | 단일 occurrence 예외 여부 |
| `series_fingerprint` | recurrence 후보를 보조 비교 |

식별자와 snapshot 검색에 필요한 인덱스는 migration에서 함께 만든다. 동일한 fingerprint만으로 자동 relink하지 않는다.

### Task Center fields

- `event_tasks`에는 `due_kind`, `relative_anchor`, `offset_minutes`, `fixed_due_at`을 둔다. 기존의 모호한 `due_offset_minutes`만으로 일정을 이동시키지 않는다.
- `personal_tasks` 테이블을 별도로 둔다. `id`, `title`, `notes`, `due_at`, `completed`, `sort_order`, `created_at`, `updated_at`, `completed_at`을 최소 필드로 사용한다.
- personal task는 EventKit/Exchange에 동기화하지 않는다.

## Status values

`event_contexts.lifecycle_status`:
- `scheduled`: 예정된 일정
- `cancelled`: 취소된 일정
- `completed`: 완료 처리된 일정
- `orphaned`: 원본 이벤트를 찾지 못한 context

`event_links.link_status`:
- `active`: 원본 이벤트와 연결됨
- `missing`: 최근 fetch에서 찾지 못했지만 복구 후보가 남아 있음
- `orphaned`: 복구 실패 후 사용자가 보관할 수 있는 상태

`event_tasks.section`:
- `before`
- `during`
- `after`

`event_change_log.change_type`:
- `created`
- `moved`
- `cancelled`
- `completed`
- `restored`
- `relinked`

`event_tasks.due_kind`:
- `none`
- `relative`
- `fixed`

## Swift domain model 초안

```swift
struct EventBrief: Identifiable, Codable, Equatable {
    let id: UUID
    var titleSnapshot: String
    var startSnapshot: Date?
    var endSnapshot: Date?
    var lifecycleStatus: EventLifecycleStatus
    var notes: String
    var tasks: [EventTask]
    var link: EventLink?
}

enum EventTaskSection: String, Codable, CaseIterable {
    case before
    case during
    case after
}

struct EventTask: Identifiable, Codable, Equatable {
    let id: UUID
    var section: EventTaskSection
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var due: TaskDue?
}

enum EventLifecycleStatus: String, Codable {
    case scheduled
    case cancelled
    case completed
    case orphaned
}

enum TaskDue: Codable, Equatable {
    case relative(anchor: RelativeAnchor, offsetMinutes: Int)
    case fixed(Date)
}

enum RelativeAnchor: String, Codable {
    case beforeStart
    case atStart
    case atEnd
    case afterEnd
}

struct PersonalTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String
    var dueAt: Date?
    var isCompleted: Bool
    var sortOrder: Int
}
```

## Identity fingerprint

Fingerprint는 복구 후보를 찾기 위한 보조 키다.
보안용 hash가 아니라 안정적인 비교 키로 취급한다.

입력 후보:
- normalized title
- normalized location
- start date bucket
- end date bucket
- calendar identifier

주의:
- 사용자가 제목이나 시간을 바꾸면 fingerprint가 달라질 수 있다.
- fingerprint 하나만으로 자동 relink하지 않는다.
- 후보가 여러 개면 사용자 확인을 거친다.

## Identity resolution 순서

1. 저장된 `event_identifier`로 직접 lookup
2. 저장된 `calendar_item_identifier`로 lookup
3. `calendar_item_external_identifier`와 `calendar_identifier` 조합으로 후보 검색
4. recurrence master identifier + occurrence date + calendar identifier 매칭
5. calendar identifier, time range, title/location snapshot으로 후보 좁히기
6. fingerprint 후보 검색
7. 복구 실패 시 `event_links.link_status = orphaned`, `event_contexts.lifecycle_status = orphaned`

## Repository 책임

`EventContextRepository`:
- context 생성, 조회, 갱신
- status 전환
- context와 link를 함께 가져오는 query

`EventTaskRepository`:
- task 생성, 수정, 삭제
- section별 ordering
- completion 상태 저장
- Task Center용 due date query

`PersonalTaskRepository`:
- personal task 생성, 수정, 삭제
- 오늘/예정/완료 목록 query

`ChangeLogRepository`:
- change log append
- context별 최신 변경 조회
- move before/after payload 저장

`CalendarRoleRepository`:
- calendar identifier별 role 저장
- 사용자 표시 이름, 색상 override, visible 상태 관리

## Migration 원칙

- migration은 한 번 적용되면 수정하지 않는다.
- schema 변경은 새 migration으로 추가한다.
- destructive migration은 v1에서 금지한다.
- migration 전 자동 backup 또는 복구 안내를 검토한다.

## Backup 원칙

Export는 SQLite DB와 metadata를 함께 묶는다.

```text
KaosCal-Backup-YYYY-MM-DD.zip
├─ kaoscal.sqlite
└─ manifest.json
```

`manifest.json`에는 최소한 아래 값을 둔다.

- app_version
- schema_version
- exported_at
- source_machine_name optional

Import는 기존 DB를 바로 덮어쓰지 않는다.
v1에서는 "현재 DB 백업 후 교체" 방식으로 시작하고, record-level merge는 v2 이후 검토한다.
