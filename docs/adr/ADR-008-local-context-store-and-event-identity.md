# ADR-008: 로컬 Context 저장소와 이벤트 연결 안전성

> 상태: Accepted
> 날짜: 2026-07-10
> 관계: ADR-003, ADR-004, ADR-006을 구체화하며 대체하지 않음

## 배경

Event Brief 메모와 작업은 Exchange 원본 일정과 수명이 다르다. EventKit 식별자는 변경될 수 있고, 반복 일정은 occurrence별로 분리되어야 하며, 종일·floating 일정은 Mac의 시간대가 바뀌어도 같은 civil occurrence에 연결되어야 한다. 저장과 식별을 느슨하게 구현하면 동시 첫 저장에서 context가 중복되거나 일정 이동 뒤 Task Center 기한이 과거 snapshot에 남을 수 있다.

## 결정

- GRDB.swift `7.10.0`을 Swift Package Manager exact version으로 고정한다.
- 앱 시작 시 Application Support의 `KaosCal/kaoscal.sqlite`를 열고 `v1_context_store` migration을 적용한다. migration/open 실패 시 in-memory DB로 대체하지 않고 기존 파일을 보존한 채 앱 사용을 중단하고 복구 안내를 표시한다.
- v1 migration에는 현재 필요한 네 테이블만 둔다: `event_contexts`, `event_links`, `event_tasks`, `personal_tasks`. change log는 Phase 6, calendar role은 Phase 8, settings·backup metadata는 Phase 9의 additive migration으로 추가한다.
- `event_contexts`와 `event_links`는 `context_id UNIQUE`인 1:1 관계다. context 삭제 시 link와 event task는 foreign-key cascade로 삭제한다. 원본 EventKit 이벤트는 이 삭제에 포함하지 않는다.
- 일정 선택이나 빈 메모는 row를 만들지 않는다. 첫 번째 비어 있지 않은 메모 또는 event task 저장 시 context와 link를 한 transaction에서 지연 생성한다.
- `DatabaseQueue`에서 식별→생성/갱신 전체를 하나의 database write transaction으로 직렬화한다. 동시 첫 저장도 context 하나만 만들며, identifier+occurrence unique index를 DB 방어선으로 둔다.
- EventKit fetch 결과를 관찰할 때 강한 식별자로 연결된 context만 같은 transaction에서 최신 title/time/source/identifier/`last_seen_at` snapshot으로 갱신한다. exact snapshot과 fingerprint는 후보만 반환하고 자동 연결하거나 갱신하지 않는다.
- 영속 연결 우선순위는 `event_identifier` → `calendar_item_identifier` → calendar+external identifier → series+occurrence identity → exact snapshot 후보 → fingerprint 후보 순서다.
- occurrence identity는 non-recurring의 `single:v1`, zoned 반복의 절대 시점 키, all-day/floating 반복의 canonical local-components 키로 구분한다. detached occurrence는 이동된 start가 아니라 원래 occurrence local components를 사용한다. UI selection identity도 local occurrence anchor를 사용해 시간대 변경에 안정적으로 유지한다.
- fingerprint는 versioned SHA-256 값이다. calendar/title/location을 정규화하고 zoned는 절대 시점, all-day/floating은 local components를 입력으로 사용한다. fingerprint 일치는 사용자 확인이 필요한 후보이며 자동 relink 근거가 아니다.
- 모든 `Date` column은 GRDB의 `.deferredToDate`를 명시해 UTC `YYYY-MM-DD HH:MM:SS.SSS` TEXT로 저장한다. 일반 GRDB `Date` binding과 같은 표현을 사용한다.
- relative event-task due는 `before_start`, `at_start`, `at_end`, `after_end` anchor와 0 이상 2,628,000분 이하 offset으로 저장한다. due가 없으면 Before/During은 일정 시작, After는 일정 종료를 파생 due로 사용한다. all-day/floating due는 조회 시 표시 calendar에서 local components를 재구성하고 fixed due만 절대 시점으로 취급한다.
- Task Center query는 event task와 personal task를 한 consistent read에서 합친다. `today`는 미완료이면서 내일 시작 전 또는 due가 없는 항목으로 overdue를 포함하고, `upcoming`은 내일 이후, `completed`는 완료 항목이다. personal task는 EventKit이나 Exchange에 동기화하지 않는다.
- KaosCal 메모·작업은 SQLite에만 쓰며 `EKEvent.notes`에는 쓰지 않는다.

## 결과

- 앱 재실행 뒤 Event Brief, event task, personal task와 완료·기한 상태를 다시 읽을 수 있다.
- 일정 이동이나 일부 EventKit identifier 변경 뒤에도 다른 강한 식별자로 연결이 유지되면 기존 notes/task를 보존하면서 snapshot과 상대 기한이 갱신된다.
- 반복 종일·floating occurrence는 Mac 시간대가 달라져 raw `Date`가 바뀌어도 같은 civil occurrence에 연결된다.
- weak identity가 같은 서로 다른 일정을 자동 병합하지 않는다.
- v1 schema는 CHECK, foreign key, unique/index 계약을 가진 immutable baseline이 된다. 이후 변경은 새 migration으로만 추가한다.

## 검토한 대안

- Event Brief를 `EKEvent.notes`에 저장: 초대·공유 일정에 영향을 주고 로컬 수명과 원본 수명을 분리할 수 없어 채택하지 않았다.
- fingerprint를 unique key로 사용: 제목·시간·장소가 같은 서로 다른 일정이 존재할 수 있어 채택하지 않았다.
- raw `occurrenceDate`만 저장: all-day/floating occurrence가 시스템 시간대 변경에 따라 다른 절대 시점으로 보일 수 있어 채택하지 않았다.
- resolve read와 create write를 분리: 동시 첫 저장에서 context 중복이 가능해 채택하지 않았다.
- DB open 실패 시 임시 in-memory 저장: 사용자가 저장 성공으로 오해한 데이터를 종료 시 잃을 수 있어 채택하지 않았다.

## 남은 검증

- 실제 `KAOS-TEST` Exchange 일정에서 identifier 변화·detached occurrence 관찰
- 실제 앱 종료/재실행 뒤 Phase 4 Event Brief와 Task Center UI 유지 확인
- 손상 DB와 migration 실패의 backup/export 복구 흐름은 Phase 9에서 완성
- orphan lifecycle과 change log는 Phase 6~7에서 additive migration으로 구현
