# ADR-010: 원본 일정 쓰기와 로컬 Context 안전 경계

- 상태: Accepted
- 날짜: 2026-07-11
- 관련: ADR-001, ADR-003, ADR-004, ADR-008, ADR-009

## 배경

Phase 5부터 KaosCal은 EventKit 원본 일정을 생성·수정·삭제한다. EventKit 식별자는 동기화나 캘린더 이동 뒤 달라질 수 있고, 편집기를 연 뒤 Calendar.app에서 원본이 바뀔 수도 있다. 원본 일정과 SQLite Event Brief는 서로 다른 저장소라 한 transaction으로 묶을 수 없으며, 참석자가 있는 회의 변경은 알림·취소 메일 같은 외부 부작용을 만들 수 있다.

이 ADR은 기존 소유권·시간·identity 결정을 구체화하며 대체하지 않는다. 실제 Exchange 호환성은 compatibility matrix의 실계정 결과로만 판정한다.

## 결정

- Phase 5 원본 write는 full calendar access가 있고 `allowsContentModifications`가 참인 비반복·비회의 일정으로 제한한다.
- `EKEvent.hasAttendees`가 참이거나 다른 organizer가 확인된 일정은 사용자가 주최자인 경우까지 Calendar.app 전용으로 둔다. KaosCal local Brief는 계속 편집할 수 있다.
- create/update/delete는 `CalendarProviding`의 명시적 명령으로만 실행한다. UI에 `EKEvent` 객체를 보관하지 않는다.
- 기존 일정은 편집 시작 snapshot을 그대로 저장하지 않는다. 같은 `EKEventStore`에서 `eventIdentifier → calendarItemIdentifier → calendarItemExternalIdentifier` 순으로 다시 찾고, 원래 calendar의 유일한 비반복 후보만 대상으로 삼는다.
- 다시 읽은 제목, calendar, 시간 의미, 장소, 원본 notes가 편집 시작 snapshot과 다르면 외부 변경으로 간주하고 아무것도 쓰지 않는다. zoned 시간은 절대 시점+zone으로, all-day/floating은 raw `Date`가 아니라 civil components로 비교해 기본 time zone 변경을 외부 편집으로 오판하지 않는다.
- no-op 저장은 EventKit save를 호출하지 않는다. 변경 시에도 바뀐 필드만 patch해, 제목만 바꾸는 작업이 좌표를 가진 structured location 같은 편집기 밖 metadata를 지우지 않게 한다.
- `EKEvent.notes`는 사용자가 명시적으로 편집하는 **원본 일정 notes**에만 사용한다. Event Brief notes와 tasks는 계속 SQLite에만 저장한다.
- 종일 일정의 편집 종료일은 UI에서 포함 날짜로 보이지만 draft와 EventKit에는 배타 종료 자정을 사용한다. timed 일정의 정확한 자정 종료를 종일로 바꿀 때 다음 날짜를 추가로 포함하지 않는다.
- draft는 편집 시작의 reference time zone을 고정한다. floating은 `timeZone == nil`, zoned는 유효한 IANA identifier다. 저장 전에 Mac 기본 time zone이 바뀌었으면 all-day/floating civil components를 새 기본 zone의 `Date`로 다시 구성하되 사용자가 고른 날짜·벽시각은 유지한다. time zone 변경은 `Keep local time`과 `Keep instant` 결과를 먼저 보여 준다.
- `Keep local time` 결과가 DST gap의 존재하지 않는 시각이거나 fall-back의 중복 시각이면 자동 보정·임의 선택하지 않고 저장을 차단한다.
- 연결된 비반복 일정의 같은-calendar 제목·시간·종일·time zone·장소·원본 notes 변경은 편집기의 `Save Changes`를 사용자 승인으로 보고 Phase 5에서 허용한다. 성공 receipt로 기존 `contextID`의 link snapshot만 명시적으로 다시 묶고 local notes/tasks는 보존한다.
- 연결된 일정을 다른 calendar로 옮기는 작업은 Phase 6 safe-move 흐름까지 차단한다. local Brief가 없는 일정만 다른 writable calendar로 옮길 수 있다.
- 연결된 원본 일정 삭제는 Phase 7 orphan review까지 차단한다. local Brief가 없는 비반복 일정만 Phase 5에서 삭제한다.
- 반복 생성·수정·삭제와 `EKSpan` 범위 선택은 Phase 6으로 이월한다.
- EventKit 저장과 SQLite rebind는 원자적이지 않다. EventKit 성공 뒤 local rebind가 실패하면 성공을 되돌린 것처럼 표시하지 않고, 원본 저장 성공·local 갱신 실패·local 데이터 보존을 함께 알린다.
- 편집기를 열기 전 pending local notes를 먼저 저장한다. 저장 실패, weak/ambiguous identity, 다른 활성 편집 세션이 있으면 원본 편집을 열지 않는다.

## 결과

- stale 원본, 반복 occurrence, read-only, 참석자 회의를 잘못 변경할 가능성이 줄어든다.
- structured EventKit metadata와 외부에서 갱신된 지원 필드는 보수적으로 보존된다.
- EventKit과 SQLite의 부분 성공을 숨기지 않으므로 사용자가 Calendar.app과 local Brief 상태를 복구할 수 있다.
- Phase 5에는 change log schema나 migration을 추가하지 않는다. 같은-calendar 시간 변경의 richer 영향 미리보기와 change log는 Phase 6에서 보강한다.
- 비반복 `KAOS-TEST` EventKit save/remove와 Outlook server 반영·UTC 정규화는 2026-07-11 signed FinalRelease gate에서 통과했다. 실제 identifier churn, Calendar.app 시각 round-trip, all-day·time-zone·반복·calendar move는 계속 별도 수동 gate다.

## 자동 검증

- draft validation, all-day 배타 종료, 자정 변환, reference time zone
- preserve-instant/local 및 DST gap/overlap 차단
- AppState create/update/delete, 제한 정책, active-session·권한 회수
- linked rebind, calendar move/delete 사전 차단, 외부 변경 오류, 부분 성공 안내
- rebind unique 충돌·missing context transaction rollback

EventKit 실제 save/remove와 Calendar.app 반영은 자동 fake-provider 결과와 구분해 compatibility matrix에 기록한다.
