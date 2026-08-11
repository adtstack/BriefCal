# ADR-012: 시간 생명주기, After Review, orphan 확인 경계

> 상태: Accepted
> 날짜: 2026-07-11
> 구현 추적: 최신 자동·Release·live 판정은 [Current Status](../current-status.md)와 [Exchange Compatibility](../exchange-compatibility.md)를 따름

## 배경

Event Brief schema에는 `scheduled`, `completed`, `cancelled`, `orphaned`와
`active`, `missing`, `orphaned`가 이미 있지만 Phase 6까지는 실제 상태 전이가
연결되지 않았다. 그 결과 종료된 일정의 Before/During 작업이 Today에 계속
남고, 원본을 찾지 못한 경우를 일정 삭제와 구분하는 제품 경계도 없었다.

일반 EventKit 구간 조회의 부재만으로 삭제를 판정할 수는 없다. 일정이 조회
구간 밖으로 이동했거나 Exchange 동기화가 지연됐거나 identifier가 바뀐
경우도 같은 결과를 만들 수 있다.

## 결정

### Phase 7A: 시간에서 파생하는 상태

- active link의 occurrence별 유효 종료 시각을 기준으로 `now >= end`이면
  `completed`, 아니면 `scheduled`다.
- 종일 일정은 배타 종료일, floating 일정은 저장한 civil components를 현재
  표시 calendar에서 재구성한 종료 시각을 사용한다.
- 시간 계산은 `scheduled`와 `completed` 사이에서만 전이한다.
  `cancelled`와 `orphaned`를 덮어쓰지 않는다.
- 일정이 미래로 이동하면 `completed`에서 `scheduled`로 돌아갈 수 있다.
- 이 전이는 관찰에서 파생한 상태이므로 `event_change_log`에 `completed`
  record를 자동으로 만들지 않는다.
- 종료된 Event Brief의 Before/During 작업은 삭제하거나 자동 완료하지 않는다.
  Today와 Upcoming의 열린 작업 projection에서만 제외하고, 미완료 After만
  남긴다.
- `After Review` 목록은 completed context의 미완료 After 작업만 보여 준다.
  personal task와 완료된 작업은 제외한다. Completed 목록은 모든 section의
  기존 완료 기록을 유지한다.

### Phase 7B: missing/orphan 확인

- 일반 구간 fetch에서 한 번 보이지 않았다는 사실은 상태 전이나 확인 횟수의
  근거가 아니며 `missing`, `orphaned`, `cancelled` 중 어느 것도 만들지 않는다.
- 사용자가 원본 열기를 명시적으로 요청했을 때 저장 link로 만든 전용 lookup을
  실행한다. query는 강한 event/item/external identifier와 반복 occurrence의
  zoned instant 또는 all-day/floating civil anchor를 함께 가진다.
- active link에 대한 첫 명시적 전용 lookup의 `notFound`만 link를
  `missing`으로 바꾼다. context lifecycle, 마지막 성공 snapshot,
  `last_seen_at`, local notes/tasks는 유지한다.
- 이미 missing인 상태에서 사용자가 `Recheck`를 명시적으로 실행하고 그 lookup도
  `notFound`일 때만 orphan 보관 확인을 제공한다. 두 번째 `notFound` 자체는
  아직 `orphaned`를 저장하지 않는다.
- 권한·provider 오류, candidate, ambiguous, calendar unavailable, 잘못된 저장
  link와 반복 occurrence를 안전하게 확정하지 못한 inconclusive 결과는 확인
  횟수로 세지 않고 상태를 바꾸지 않는다.
- 어느 calendar에서든 강한 identifier seed가 보이지만 저장한 recurrence shape나
  exact occurrence anchor가 확인되지 않으면 `notFound`가 아니라
  `strongIdentifierOccurrenceMismatch` 또는 `recurringOccurrenceUnavailable`
  inconclusive로 끝낸다. 같은 series의 sibling occurrence를 자동 선택하지 않는다.
- EventKit의 first-occurrence identifier seed와 bounded search는 살아 있는 series에서
  멀리 이동한 detached occurrence와 삭제된 occurrence를 확실히 구분하지 못한다.
  이 경우 Phase 7B는 자동 missing/orphan 확인을 주장하지 않고 local data를 그대로
  둔 채 manual exact-occurrence relink만 제공한다.
- 유일한 강한 `.found`는 missing link를 active로 복구하고 snapshot과 시간
  lifecycle을 갱신한다. EventKit의 명시적 canceled status는 부재가 아니라
  cancellation 증거이므로 link는 active로 유지하고 context를 `cancelled`로
  표시한다. 이후 non-cancelled `.found`가 확인되면 `cancelled`를 해제하고 현재
  종료 시각에서 `scheduled`/`completed`를 다시 계산한다. 이 provider 관찰은
  Phase 7C의 사용자 원본 삭제가 아니므로 `cancelled` change log를 만들지 않는다.
- `Keep as orphan`, 명시적 후보 `Relink`, `Delete local Brief`는 서로 다른
  사용자 명령이다. Keep은 context/link를 함께 orphaned로 만들고 local data를
  보존한다. local 삭제는 missing/orphaned Brief의 SQLite context만 cascade
  삭제하며 EventKit create/update/delete를 호출하지 않는다.
- 후보 Relink는 사용자가 고른 event를 provider에서 한 번 더 occurrence-aware
  strong lookup해 유일한 `.found` 또는 `.cancelled`임을 확인한다. 그 뒤 선택
  시작 때의 `EventLink`와 현재 row가 완전히 같은지 expected-link CAS로 검사하고,
  strong identifier·다른 context 충돌도 확인한다. 통과하면 link snapshot,
  lifecycle, 이전 available Undo supersede와 `relinked` log append를 한 SQLite
  transaction에서 수행하며 local notes/tasks는 보존한다. 최종 검증 결과가
  `.cancelled`인 후보는 relink 후 lifecycle도 `cancelled`로 유지한다.
- relink의 before log는 v1 `event_links`에 저장된 마지막-known 값으로 만든다.
  v1은 원본 EventKit notes를 저장하지 않았으므로 `before.originalNotes`는
  `nil`(unavailable)이다. 이 빈자리에 BriefCal local notes를 대입하지 않는다.

위 선행 결정에 따라 `CalendarProviding`에 저장 link 또는 최종 선택 event에서
만드는 `CalendarEventLookupQuery`와 typed result를 추가했다. Phase 7B는 기존
v1/v2 status, snapshot, foreign key와 `relinked` change type을 재사용하므로 schema
migration을 추가하지 않았다.

### Phase 7C: 연결된 원본 삭제

- linked original delete는 active link의 notes 글자 수, Before/During/After task
  수와 제목, 최근 history, 원본 calendar/time과 반복 scope를 read-only로 준비해
  보여 준다. 첫 삭제 alert와 review의 Back은 EventKit/SQLite를 바꾸지 않으며
  `Delete Original & Keep Brief` 최종 Confirm만 write 권한이다.
- preparation은 저장된 `EventLink`와 여기서 만든 `EventChangeSnapshot`을 함께
  고정한다. Confirm 직전 현재 link 전체와 saved snapshot이 그대로인지 다시
  검사하고, EventKit 성공 뒤 local finalize transaction에서도 같은 equality CAS를
  반복한다. stale/missing/non-active link는 provider 호출 전에 중단한다.
- 비반복 linked event는 change-log `single`, 반복 occurrence 하나는 `this_event`로
  삭제한다. linked 반복의 `futureEvents`, attendee meeting, invitation, read-only
  원본은 계속 provider 호출 전에 차단한다.
- 성공한 EventKit 삭제는 하나의 SQLite transaction에서 context lifecycle을
  `cancelled`, link status를 `orphaned`로 바꾸고 이전 available Undo를 supersede한
  뒤 unavailable `cancelled` log를 append한다. 같은 `contextID`, link의 마지막-known 값,
  `last_seen_at`, local notes/tasks는 보존한다.
- 삭제 log는 저장 link에서 만든 snapshot을 before/after에 똑같이 사용한다.
  post-delete event가 없으므로 `change_type = cancelled`가 제거 의미를 전달한다.
  v1 link는 원본 EventKit notes를 저장하지 않았으므로 두 payload의
  `originalNotes`는 `nil`(unavailable)이며 BriefCal local notes를 대입하지 않는다.
  undo state는 `unavailable`이고 delete용 session Undo token을 만들지 않는다.
- `Original deleted` provenance는 `cancelled + orphaned` 상태쌍 자체가 아니다.
  현재 context history에 unavailable `cancelled` log가 있고 그 뒤에 더 최신
  `relinked` log가 없어야 한다. 최신 판단은 `created_at`을 먼저 비교하고 같은
  timestamp에서는 SQLite `rowid`를 tie-break로 사용한다. 더 늦은 relink는 과거
  deletion provenance를 무효화하므로 이후 외부 cancellation/orphan 전이가 같은
  상태쌍을 만들어도 새 BriefCal deletion log 없이는 deleted-original로 표시하지 않는다.
- status, `cancelled` change type, `single`/`this_event` scope와 unavailable Undo는
  기존 v1/v2 schema에 모두 있어 Phase 7C migration을 추가하지 않았다.
- EventKit remove와 SQLite finalize는 하나의 transaction이 아니다. provider가
  성공했지만 receipt가 모순되거나 local CAS/log transaction이 실패하면 editor와
  review를 닫고 refresh하며 같은 Delete를 재시도하지 않도록 한다. 원본은 이미
  삭제됐거나 삭제됐을 수 있고 local Brief/notes/tasks는 rollback으로 보존됐음을
  함께 알린다. 두 경계 사이 process 종료도 같은 crash window이며 Phase 7B의
  보수적 recovery가 fallback이다. 자동으로 원본을 재생성하지 않는다.
- Task Center와 recovery sheet는 `cancelled + orphaned`에 current-link-generation
  deletion provenance가 함께 있을 때만 `Original deleted · Local Brief kept`로
  표시한다. 그 외 같은 상태쌍은 일반 local orphan으로 남기며 Relink 또는 local
  Brief 삭제 진입점을 유지한다.

## 결과

Phase 7A는 Exchange 원본을 쓰지 않고도 종료 후 작업 흐름을 제공한다.
완료된 Phase 7B는 조회 누락을 삭제로 오인하지 않고 원본 일정과 local Brief의
삭제 권한을 분리한다. Phase 7C는 사용자가 명시적으로 시작한 원본 삭제에만
positive EventKit receipt를 사용해 `cancelled + orphaned`와 current-link-generation
unavailable cancellation provenance를 기록한다. 전용 lookup,
두 단계 notFound, 보수적 반복 판정, 검증된 relink, local-only delete와 linked
original delete review/finalize는 schema 변경 없이 기존 v1/v2 저장 계약 위에
구현했다. 자동 checkpoint는 fake provider/local DB 범위이며 실제 Exchange linked
delete와 Calendar.app/서버 반영은 별도 수동 gate다.
