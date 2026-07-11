# ADR-004: 초대 일정과 Event Brief 연결 안전성

> 상태: Accepted
> 날짜: 2026-07-10

## 배경

초대 일정 변경은 Exchange 메일과 참석자에게 영향을 줄 수 있고, EventKit ID는 sync·반복·일정 이동에 따라 달라질 수 있다.

## 결정

- 초대 일정은 표시와 local-only Event Brief·작업만 허용한다.
- RSVP, 참석자, organizer, 초대 원본 일정 변경·삭제는 v1에서 제공하지 않는다.
- Event Brief는 사용자가 처음 메모나 작업을 저장할 때 지연 생성한다.
- 연결 복구는 event ID, calendar item ID, external ID, calendar ID, recurrence occurrence 정보, snapshot, fingerprint 순서로 보수적으로 수행한다.
- 후보가 둘 이상이면 자동 relink하지 않고 사용자에게 확인을 요청한다.
- 원본이 한 번 안 보였다고 context를 삭제하지 않는다. 첫 전용 `notFound`는 missing만 기록하고, missing 재확인의 두 번째 `notFound`는 review만 연다. 사용자가 `Keep as orphan`을 승인한 뒤에만 context/link를 orphaned로 전환하며 재연결·local 삭제는 별도 명령이다.

## 결과

`moved`는 lifecycle status가 아니라 change log event다. lifecycle은 scheduled, completed, cancelled, orphaned로 분리한다.
