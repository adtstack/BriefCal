# ADR-014: 캘린더 역할·가상 Set·중복 후보의 로컬 투영

> 상태: Accepted
> 날짜: 2026-07-12
> 후속 확장: ADR-018이 saved Calendar Set과 persisted selection을 추가한다.

## 배경

KaosCal은 EventKit의 calendar title, source, account type, color와 writable 상태를
표시하지만, 여러 계정을 함께 사용할 때 사용자가 정한 Work/Personal 같은 의미는
EventKit에 없다. 같은 일정이 여러 캘린더에 복제돼도 원본 식별자만으로 자동
병합하거나 삭제할 수 없고, EventKit은 공유 Exchange 캘린더가 읽기 전용인 구체
ACL 원인을 항상 제공하지 않는다.

Phase 8은 화면마다 제각각이던 source·permission 설명을 통일하면서도 원본 일정,
Event Brief identity, change log와 Exchange 동기화 경계를 바꾸지 않아야 한다.

## 결정

- `CalendarSource`와 `DisplayEvent`는 EventKit raw snapshot으로 유지한다. 사용자
  역할을 이 값이나 `EventLink`·`EventChangeSnapshot`에 덮어쓰지 않는다.
- 역할은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`의 로컬
  projection이다. subscribed/birthdays만 `Subscription`을 기본값으로 추론하고,
  그 외 캘린더는 이름·계정 종류만으로 용도를 추측하지 않아 `Other`로 둔다.
- 사용자가 변경한 역할만 additive `v3_calendar_clarity`의
  `calendar_preferences`에 sparse upsert한다. 단순 EventKit 조회는 row를 만들지
  않으며 role 변경은 `CalendarProviding`을 호출할 수 없는 local repository에서만
  수행한다.
- Phase 8 당시 Calendar Set은 `All`과 역할별 virtual filter였다. raw fetch, Event Brief
  관찰, missing/relink와 editor의 writable destination 목록은 필터링하지 않고
  Day/Week/Agenda 표시만 좁힌다. 이후 ADR-017은 global visibility를, ADR-018은 이름 있는
  exact-membership saved Set과 selection persistence를 additive 확장으로 추가한다.
- 수정 불가 사유는 invitation, attendee meeting, subscribed calendar,
  birthdays calendar, provider-reported read-only 순서의 typed projection으로
  통일한다. Exchange/CalDAV/iCloud의 소유자·관리자 ACL을 추측하지 않는다.
- 중복 감지는 서로 다른 캘린더에서 정규화 title과 보수적인 시간 범위가 맞는
  항목을 `Possible duplicate` 후보로만 보여 주는 비영속 read projection이다.
  동일 strong identity/occurrence는 제외하고 자동 병합·숨김·삭제·원본 write를
  제공하지 않는다.
- source, role과 typed permission은 Day/Week/Agenda/Inspector의 시각 텍스트·help·
  VoiceOver에 일관되게 포함하고 중복 표시는 이 화면들과 Inspector 후보 목록에 둔다.
  Task Center는 저장 calendar identifier로 calendar/source/role만 투영한다. 작은
  timeline card의 밀도는 유지하고 자세한 이유와 후보 목록은 Inspector를 기준
  화면으로 삼는다.

## 2026-07-15 mini month projection 확장

- 구현된 `UI-005`에서 Calendar Set의 display projection은 Day/Week/Agenda뿐 아니라
  mini month 일정 존재 표시에도 적용한다. 자동 계약은 통과했으며 실창·VoiceOver는
  별도 live gate로 남긴다.
- mini month 요약은 `global Enabled ∩ 선택 Calendar Set`만 사용하고 availability
  blocking과는 독립이다. raw fetch, Event Brief 관찰·복구, duplicate review와 editor
  destination을 줄이지 않는다는 기존 비파괴 경계는 그대로 유지한다.

## 결과

사용자는 여러 계정의 캘린더를 자기 의미로 분류하고 역할별로 볼 수 있으며,
읽기 전용 원인과 비슷한 일정 후보를 원본 변경 없이 확인할 수 있다. 역할 설정은
Exchange/Calendar.app의 calendar 이름·색·권한을 바꾸지 않고 로컬 DB backup 대상이
된다.

Phase 8의 가상 role Set은 현재 UI에서 Smart Role Filter로 구분한다. saved Set의 완성형
계약은 [ADR-018](ADR-018-saved-calendar-sets.md)을 따르며 duplicate 후보는 여전히 확정
판정이 아니다.
공유 read-only Exchange 캘린더의 실제 설명과 긴 source/role 조합은 별도 live UI
gate에서 검증해야 한다.
