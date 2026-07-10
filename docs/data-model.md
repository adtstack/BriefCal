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

Phase 4는 EventKit 객체를 UI 값 snapshot으로 분리하고, 필요한 연결·맥락만 SQLite에 영속화하며 두 local 편집 화면의 projection을 AppState에서 조정한다.

| 값 | 역할 | 영속 모델과의 차이 |
| --- | --- | --- |
| `DisplayEvent` | title, source, calendar color, raw date, read-only, invitation, recurrence를 UI에 전달 | 앱 재실행 뒤 영속 ID로 사용하지 않음 |
| `EventTimeSemantics` | `allDay`, `floating`, `zoned` 구분 | `event_links.time_semantics`와 local component snapshot으로 변환 |
| `LocalDateTimeComponents` | 원 calendar identifier와 civil components 보존 | all-day/floating 표시·due·반복 occurrence 재구성에 사용 |
| `DisplayEventIdentity` | SwiftUI selection과 occurrence별 card identity | `external → calendar item → event` 우선순위, local occurrence anchor 사용; 영속 resolver와 목적이 다름 |
| `CalendarEventLayout` | visible period의 timed/all-day placement | 파생값이므로 저장하지 않음 |

영속 Event Brief 연결은 아래 `Identity resolution 순서`로 구현되어 있다. UI ID가 같거나 달라졌다는 사실만으로 local context를 자동 연결·삭제하지 않는다.

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

## 구현된 V1 baseline

첫 GRDB migration `v1_context_store`는 아래 네 테이블만 만든다.

| 테이블 | 현재 책임 |
| --- | --- |
| `event_contexts` | Event Brief title/time snapshot, lifecycle, local notes |
| `event_links` | EventKit identifiers, source/time/recurrence snapshot, identity 후보 |
| `event_tasks` | Before/During/After, ordering, completion, fixed/relative due |
| `personal_tasks` | 독립 개인 할 일, due, ordering, completion |

모든 `Date` column은 GRDB `.deferredToDate`를 명시해 UTC millisecond TEXT로 저장한다. foreign key를 항상 켜고, context 삭제는 link와 event task에만 cascade한다.

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
| `recurrence_series_identifier` | 반복 series 후보 연결. EventKit이 master 객체를 보장한다는 의미를 쓰지 않음 |
| `occurrence_date` | occurrence별 Event Brief 연결 |
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

계획된 `event_change_log.change_type`(Phase 6):
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

## Swift domain model

실제 record는 String ID를 사용하는 `EventContext`, `EventLink`, `EventTask`, `PersonalTask`다. `EventBriefSnapshot`은 context+link+tasks 조회 결과이며 별도 테이블이 아니다. `TaskCenterItem`도 event/personal record를 합친 파생값이라 저장하지 않는다.

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
7. 현재는 `notFound`를 반환한다. missing/orphaned lifecycle 전환은 Phase 6~7에서 구현한다.

1~4의 강한 연결만 EventKit fetch 관찰 시 title/time/source/identifier/`last_seen_at` snapshot을 자동 갱신한다. 5~6은 `candidate` 또는 `ambiguous`로 반환해 사용자 확인 전에는 쓰지 않는다.

## Repository 책임

`AppDatabase`:
- `DatabaseQueue` open과 `v1_context_store` migration
- foreign key 활성화
- production Application Support, test in-memory/temporary-file 경계

`EventContextRepository`:
- context/link/brief 조회와 snapshot 갱신 primitive
- context와 link를 함께 가져오는 query

`ContextStore`:
- identity resolution과 첫 context/link 생성의 transaction 경계
- EventKit fetch 관찰 시 강한 link snapshot refresh
- weak candidate의 자동 연결 차단
- lazy Brief load와 context-scoped event task mutation
- side-effect-free navigation target read와 strong-only inverse event match
- typed Task Center completion routing과 missing/context mismatch 방어

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
- typed backing task identity와 event section/effective range projection
- `Today`: 미완료이며 내일 시작 전 due 또는 due 없음. overdue를 포함
- `Upcoming`: 미완료이며 내일 시작 이후 due
- `Completed`: event/personal 완료 항목을 완료 시각 역순으로 결합

계획된 `ChangeLogRepository`(Phase 6):
- change log append
- context별 최신 변경 조회
- move before/after payload 저장

계획된 `CalendarRoleRepository`(Phase 8):
- calendar identifier별 role 저장
- 사용자 표시 이름, 색상 override, visible 상태 관리

## Migration 원칙

- `v1_context_store`는 Phase 3에서 적용·검증된 immutable baseline이다.
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
