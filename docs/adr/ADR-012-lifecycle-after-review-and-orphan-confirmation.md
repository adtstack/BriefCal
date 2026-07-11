# ADR-012: 시간 생명주기, After Review, orphan 확인 경계

> 상태: Accepted
> 날짜: 2026-07-11

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

- 일반 구간 fetch에서 한 번 보이지 않았다는 사실은 `orphaned`나
  `cancelled`의 근거가 아니다.
- 전용 lookup은 강한 event/item/external identifier와 반복 occurrence의
  civil/instant anchor를 함께 사용해야 한다.
- 첫 전용 lookup의 `notFound`는 link를 `missing`으로만 표시한다.
- 이미 missing인 상태에서 사용자가 명시적으로 다시 확인한 lookup도
  `notFound`일 때만 orphan 보관 확인을 제공한다.
- 권한·provider·동기화 오류는 확인 횟수로 세지 않는다. weak/ambiguous
  candidate는 자동 연결하지 않는다.
- `Keep as orphan`, 명시적 후보 `Relink`, `Delete local Brief`는 서로 다른
  사용자 명령이다. local 삭제는 EventKit 삭제를 호출하지 않는다.

Phase 7B를 열기 전에 `CalendarProviding`에 저장 link로부터 만든 전용 lookup
query/result를 추가한다. 현재의 부분 구간 `fetchEvents`만으로 자동 orphan
전이를 구현하지 않는다.

### Phase 7C: 연결된 원본 삭제

- linked original delete는 notes와 section별 task 영향을 먼저 보여 준 뒤
  별도 Confirm을 요구한다.
- 성공한 EventKit 삭제는 context를 `cancelled`, link를 `orphaned`로 바꾸되
  local notes/tasks를 보존한다.
- 삭제 change log는 저장 link에서 만든 마지막-known snapshot을 사용한다.
  post-delete 이벤트가 없으므로 `cancelled`의 before/after payload는 같은
  snapshot이고 `change_type`이 제거 의미를 전달한다.
- linked 반복의 `futureEvents` 삭제, attendee meeting과 invitation 원본 삭제는
  계속 차단한다.

## 결과

Phase 7A는 Exchange 원본을 쓰지 않고도 종료 후 작업 흐름을 제공한다.
Phase 7B/C는 조회 누락을 삭제로 오인하지 않으며, 원본 일정과 local Brief의
삭제 권한을 분리한다. schema 변경은 필요 없지만 7B/C 구현에는 전용 provider
lookup, orphan review UI, 저장 link 기반 change snapshot과 별도 회귀 검증이
필요하다.
