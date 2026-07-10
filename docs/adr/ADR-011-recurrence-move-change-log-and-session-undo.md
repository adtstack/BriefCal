# ADR-011: 반복 범위·안전한 이동·변경 기록과 세션 Undo

- 상태: Accepted
- 날짜: 2026-07-11
- 관련: ADR-003, ADR-004, ADR-008, ADR-009, ADR-010

## 배경

Phase 6은 반복 occurrence 변경과 local Event Brief가 연결된 일정의 calendar 이동을 다룬다. 두 작업은 EventKit identifier·series 구조를 바꿀 수 있고, `futureEvents`는 한 occurrence가 아니라 이후 series 전체에 영향을 준다. EventKit 원본과 SQLite context는 하나의 transaction으로 묶을 수 없으므로 확인 UI, local rebind, change log, undo가 실제 성공 범위를 과장하지 않아야 한다.

이 ADR로 Phase 6 구현 계약을 고정했고 코드·자동 테스트 gate를 통과했다. 다만 실계정 Exchange 통과는 선언하지 않으며, 실제 지원 범위는 compatibility matrix의 `KAOS-TEST` 결과로만 연다.

## 결정

### 1. 반복 write에는 명시적인 범위가 필요하다

- 기존 반복 occurrence의 수정·이동·삭제는 `이번 일정`(`thisEvent`) 또는 `이번 이후`(`futureEvents`) 중 하나를 사용자가 고르기 전에는 provider를 호출하지 않는다.
- `이번 일정`은 선택 occurrence 하나만 대상으로 하며 EventKit이 detached occurrence를 만들 수 있음을 확인 화면에 알린다. 기존 detached occurrence에도 강한 identity와 fresh snapshot이 있으면 이 범위만 허용할 수 있다.
- 기존 series의 recurrence rule 자체를 바꾸는 작업은 `이번 이후`에서만 허용한다. `이번 일정`은 선택 occurrence의 지원 상세만 바꾸며 series rule을 쓰지 않는다. linked series는 초기 Phase 6에서 `이번 이후`가 차단되므로 recurrence rule 변경도 Calendar.app으로 안내한다.
- detached occurrence에서 `이번 이후`는 series 경계가 모호하므로 차단하고 Calendar.app으로 안내한다.
- 기본 일·주·월·년, interval, 종료, 주간 요일처럼 KaosCal이 손실 없이 표현할 수 있는 단일 규칙만 편집한다. 여러 규칙이나 안전하게 왕복할 수 없는 복잡한 서버 규칙은 그대로 보존한다. 해당 occurrence의 title/time/calendar/location/original notes 같은 일반 필드는 `이번 일정`에서 recurrence rule을 건드리지 않고 편집할 수 있지만, `이번 이후`와 recurrence rule 변경은 Calendar.app 전용이다.
- 새 반복 series는 지원 가능한 기본 규칙으로만 만든다. 기존 series를 단순 규칙으로 재구성해 알 수 없는 필드를 덮어쓰지 않는다.
- 기존 단일 일정을 새 series로 변환하는 control은 초기 Phase 6에 넣지 않는다.
- attendee가 있는 meeting과 invitation은 반복 여부와 관계없이 계속 Calendar.app 전용이다.

### 2. 위험한 write는 확인 뒤에만 실행한다

- 반복 write, calendar 이동, 기존 일정의 시간·종일·time-zone 의미 변경은 저장 전에 immutable impact preview를 만든다. linked context가 있으면 유지될 local 항목도 함께 계산한다.
- 확인 화면은 작업 종류, 반복 범위, 기존/새 calendar, 기존/새 시간 의미, 유지할 현재 Event Brief notes와 Before/During/After task 요약, 예상되는 detach 또는 series split을 표시한다. linked future는 이 화면까지 진행하지 않고 사전 차단한다.
- 사용자가 확인한 뒤에도 provider는 같은 long-lived store에서 원본을 다시 찾고 fresh snapshot과 현재 권한을 재검증한다. 확인은 stale 원본이나 read-only 상태를 무시하는 권한이 아니다.
- Cancel, sheet 닫기, validation 실패에는 EventKit write, local rebind, change log append가 모두 없어야 한다.
- title·location·원본 notes만 바꾸는 같은-calendar 비반복 수정은 Phase 5의 `Save Changes` 승인을 유지할 수 있다. 영향 범위가 넓어지는 변경만 추가 확인을 요구한다.

### 3. linked calendar 이동은 context를 재생성하지 않는다

- target calendar는 현재도 writable이어야 하며, source calendar와 target calendar를 확인 화면에서 명시한다.
- EventKit save 성공 receipt를 기준으로 기존 `contextID`의 link identifier·calendar·시간·recurrence snapshot을 명시적으로 다시 묶는다. notes와 tasks는 그대로 보존한다.
- EventKit save는 성공했지만 identifier churn으로 post-save occurrence receipt를 강하게 확정하지 못하면 부분 성공으로 전파한다. UI는 editor/review를 닫고 refresh해 동일 write 재시도를 막으며, “재시도하지 말고 Calendar.app에서 확인”을 안내한다. 이 경로는 local rebind·change log·Undo token을 만들지 않고 기존 Event Brief를 보존한다.
- 비반복 linked move와 안전하게 식별 가능한 `thisEvent` move는 기존 context 하나를 rebind한다.
- `futureEvents`가 영향을 주는 local context를 모두 열거하고 각 occurrence를 강하게 재연결할 계획을 만들 수 있어야 linked future-series write를 열 수 있다. Phase 6의 첫 안전 범위는 이 multi-context reconciliation을 제공하지 않으므로 linked `futureEvents`를 모두 provider 호출 전에 차단한다. 후속 구현도 하나라도 weak·ambiguous·missing이거나 series split 뒤 occurrence 대응을 보장할 수 없으면 계속 차단해야 한다.
- linked 원본 삭제는 반복 범위와 무관하게 Phase 7 orphan review까지 차단한다. Phase 6의 delete 범위 UI는 local Brief가 없는 반복 일정에만 적용할 수 있다.

### 4. change log는 additive local schema다

- immutable `v1_context_store`를 수정하지 않고 새 additive migration `v2_event_change_log`로 `event_change_log` table을 추가한다.
- log는 Event Brief가 연결된 원본 변경에만 append한다. 단순 EventKit 관찰이나 실패·취소·no-op은 기록하지 않는다.
- 최소 record는 `id`, `context_id`, `change_type`, `scope`, `before_payload`, `after_payload`, `undo_state`, `undone_at`, `undo_of_change_id`, `created_at`을 가진다. `change_type`은 `created`, `details_updated`, `moved`, `recurrence_changed`, `cancelled`, `completed`, `restored`, `relinked`, `scope`는 `single`, `this_event`, `future_events`로 제한한다.
- versioned payload는 identifier, calendar/source, title/location/original event notes, 정확한 raw time과 all-day/floating civil components 또는 zoned identifier, recurrence occurrence identity를 담아 확인과 안전한 역방향 write에 사용한다. 이는 이 Mac의 local DB에 저장되는 원본 snapshot이며 계정 자격 증명, 참석자, Event Brief notes/tasks 본문은 담지 않는다.
- `undo_state`는 `available`, `superseded`, `undone`, `unavailable`로 제한한다. `undo_of_change_id`는 같은 table의 원본 변경을 가리키며 한 변경을 두 번 undo하지 못하도록 unique index를 둔다.
- `undone` row만 non-null `undone_at`을 가지며, `restored` row는 non-null `undo_of_change_id`와 `unavailable` state를 함께 가져야 한다. 원본 change가 local context와 함께 삭제되면 self-reference도 cascade한다.
- EventKit 성공 뒤 linked rebind와 change log append는 하나의 SQLite transaction에서 수행한다. transaction이 실패하면 원본 EventKit 성공과 local 갱신 실패를 함께 알리고 local data를 보존한다. 성공하지 않은 local transaction을 change log가 성공으로 위장하면 안 된다.

### 5. Undo는 마지막 작업의 세션 내 보조 기능이다

- Phase 6 Undo는 영속 history rollback이나 앱 재실행 뒤 복원이 아니다. 성공한 write 직후 메모리에 보관한 단 하나의 undo token만 사용한다.
- v1의 session Undo 대상은 local context가 연결되고 strong identity로 다시 찾을 수 있는 비반복 `single` calendar/time 변경 중 명령이 명시적으로 `available`로 기록한 마지막 한 건으로 제한한다. unlinked write, details-only write, 반복 `thisEvent`/`futureEvents`, series split, detached occurrence, delete는 Undo 대상이 아니다.
- 이후 성공한 KaosCal 원본 write, 권한 상실, 앱 종료가 발생하면 token을 폐기한다. 일반 EventKit refresh나 store-change 알림만으로 즉시 폐기하지 않는다. 자체 save 알림이 방금 만든 Undo를 지우지 않아야 하기 때문이다.
- 외부 변경 뒤 button이 잠시 남을 수 있어도 Undo는 현재 원본을 strong identity로 다시 찾고 직전 after snapshot과 같은지 provider에서 fresh stale-check한 뒤에만 역방향 EventKit write를 실행한다. missing·read-only·attendee·stale이면 local mutation 전에 중단한다. 성공하면 이전 change log를 지우지 않고 원본 record를 `undone`으로 바꾸며 `undo_of_change_id`가 원본을 가리키는 별도 `restored` record를 같은 transaction에서 append한다. 새로 undo 가능한 변경이 생기면 이전 `available` record는 `superseded`가 된다.
- Undo가 불가능하거나 실패해도 자동 보정·Calendar.app 재수정·local context 삭제를 하지 않는다. 실제 원본과 local 상태를 설명하고 사용자가 Calendar.app에서 확인하도록 한다.

## 결과

- 반복 범위와 calendar 이동 영향이 write 전에 드러나며 Cancel은 side effect가 없다.
- series split이나 identifier churn을 안전하게 reconciliation할 수 없는 linked future write는 기능 제공보다 데이터 보존을 우선해 차단된다.
- change log는 EventKit 성공과 local transaction 성공을 구분하고, Event Brief와 같은 local 수명을 가진다.
- Undo를 좁게 제한해 외부 동기화나 반복 series를 과거 상태로 덮어쓸 위험을 줄인다.
- linked 삭제와 orphan lifecycle은 계속 Phase 7 범위다.

## 검증 기준

- 범위 선택과 최종 확인 전 provider call 0회, log row 0개
- `thisEvent`와 `futureEvents`의 provider span·impact preview 분리
- detached `futureEvents`, complex recurrence의 future/rule 변경, attendee meeting 차단과 complex `thisEvent` 상세 변경 시 rule 보존
- linked move 뒤 같은 `contextID`·notes·tasks 유지와 move log append
- 초기 Phase 6의 모든 linked future는 provider 호출 전 차단
- EventKit 성공·SQLite 실패의 부분 성공 표시와 false log 방지
- post-save occurrence receipt 실패 시 editor/review 종료, refresh, 동일 write 재시도 차단, local data·log 불변
- session Undo token의 생성·무효화·one-shot 역방향 write
- 전체 **121 tests, 0 failures, 0 unexpected** 자동 gate 통과
- 실제 Exchange KC-E4와 calendar move는 별도 수동 gate에서만 pass 판정
