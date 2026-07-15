# ADR-017: 캘린더 표시와 가용시간 차단을 독립 정책으로 둔다

> 상태: Accepted
> 날짜: 2026-07-15
> 관계: ADR-014, ADR-016, ADR-018

## 배경

역할별 virtual Calendar Set만으로는 여러 계정의 캘린더를 충분히 구성할 수 없다.
생일·공휴일처럼 화면에는 보여도 빈 시간을 막지 않아야 하는 캘린더가 있고, 개인
일정처럼 상세 화면에서는 숨겨도 이중 예약 방지를 위해 시간을 막아야 하는 캘린더가
있다. 표시 여부를 가용시간 계산의 입력으로 재사용하면 이 두 경우를 표현할 수 없다.

EventKit은 calendar source identifier와 event별 free/busy availability를 제공한다.
반면 source/calendar 제목은 계정 identity가 아니며, 읽기 전용이라는 사실도 일정이
사용자의 시간을 점유하는지 판정하는 근거가 아니다.

## 결정

- calendar별 `isVisible`과 `blocksAvailability`를 독립된 local projection으로 둔다.
  `show+block`, `show+ignore`, `hide+block`, `hide+ignore` 네 조합을 모두 허용한다.
- EventKit `sourceIdentifier`를 `CalendarSource` snapshot에 포함해 Settings에서 계정별로
  묶는다. 같은 제목을 identifier 대신 사용하지 않고 reconnect 뒤 새 identifier에
  제목만으로 설정을 자동 이식하지 않는다.
- 역할 sparse row와 사용 정책 sparse row를 분리한다. additive migration
  `v8_calendar_usage`가 추가하는 `calendar_usage_preferences`는 calendar identifier와
  source/calendar snapshot, nullable visibility/blocking override만 저장한다. 두 override가
  모두 `NULL`인 row는 허용하지 않으며 단순 EventKit 조회는 row를 만들지 않는다.
- 기존 사용자 표시를 보존하기 위해 모든 calendar는 기본 표시한다. Exchange, CalDAV,
  iCloud, local과 unknown calendar는 기본적으로 시간을 막고 subscribed/birthdays는
  기본적으로 막지 않는다. read-only 여부나 제목으로 blocking 기본값을 바꾸지 않는다.
- event별 최종 차단은 calendar blocking 정책과 EventKit event snapshot을 함께 사용한다.
  free, canceled, 현재 사용자가 declined한 event는 막지 않는다. busy, tentative,
  unavailable과 availability 미지원 event는 MVP에서 보수적으로 막는다.
- `visibleEvents`는 `global calendar visibility ∩ selected Calendar Set`으로 계산한다.
  선택이 All이면 모든 enabled calendar, role Smart Filter면 해당 role, saved Set이면
  exact membership을 사용한다. global disable은 saved membership을 삭제하지 않는다. 가용시간은
  `visibleEvents`가 아니라 raw fetched events에서 계산하고 겹치거나 맞닿은 interval을
  union한다. 따라서 숨긴 calendar도 시간을 막을 수 있고 중복 interval이 가중되지 않는다.
- usage 설정은 Day/Week/Agenda 표시와 가용시간 projection에만 영향을 준다. EventKit raw
  fetch, Event Brief 관찰/identity, missing/relink, duplicate review와 writable destination은
  필터링하지 않으며 Calendar/Exchange 원본 write를 수행하지 않는다.
- Settings는 source identifier별 account group에 Show, Block, Role을 제공하고 현재 account의
  show/block bulk action을 지원한다. Sidebar의 eye는 빠른 visibility 전환이고 clock 표시는
  blocking 상태 설명이다.

## 결과

사용자는 계정 안의 calendar마다 노출과 충돌 방지 참여를 별도로 정할 수 있다. 정책은
KaosCal SQLite backup/reset 대상이며 EventKit 원본을 바꾸지 않는다. `v8` 도입 뒤에도
strict backup 계약은 current-schema exact match만 허용하므로 이전 schema ZIP을 자동
migration하지 않는다.

현재 구현은 free/busy projection과 merged blocked interval까지 제공하며 자동 일정 배치나
회의 추천 UI는 제공하지 않는다. tentative를 soft conflict로 분리하는 정책, account-level
default inheritance와 identifier churn 수동 복구는 후속 결정이다.
