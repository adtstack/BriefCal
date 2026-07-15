# ADR-018: 이름 있는 Calendar Set과 exact membership을 로컬에 저장한다

> 상태: Accepted
> 날짜: 2026-07-15
> 관계: ADR-014, ADR-015, ADR-017 확장

## 배경

Phase 8의 `CalendarSetFilter`는 `All`과 role별 filter만 제공했다. 이는 역할별 Smart
Filter로는 유용하지만, 서로 다른 role·account의 calendar를 한 이름 아래 묶거나 같은
calendar를 여러 조합에 포함하는 일반적인 saved Calendar Set 의미를 충족하지 않는다.

한편 v8의 global visibility와 availability blocking은 서로 독립이다. saved membership을
추가하면서 visibility를 membership으로 덮어쓰거나, 화면에 보이지 않는다는 이유로 busy
time을 무시하면 기존 네 가지 usage 조합과 이중 예약 방지 경계가 깨진다.

## 결정

- `CalendarSetFilter`는 synthetic `All`, role별 Smart Filter, saved Set ID를 구분한다.
  `All`과 role filter는 `calendar_sets` row가 아니다. Work/Personal 같은 role도 saved
  membership으로 가장하지 않는다.
- additive `v9_saved_calendar_sets`가 다음 local table을 추가한다.
  - `calendar_sets`: stable ID, case-insensitive unique name, sort order와 timestamp
  - `calendar_set_memberships`: stable row ID, set FK, exact calendar identifier,
    source identifier/source title/calendar title snapshot, sort order와 timestamp
  - `calendar_set_selection`: role 또는 saved Set 중 하나만 가질 수 있는 singleton
- 한 saved Set에는 같은 calendar identifier를 한 번만 넣지만, 한 calendar는 여러 saved
  Set에 들어갈 수 있다. membership은 role과 독립이므로 서로 다른 role의 calendar도 같은
  Set에 함께 들어갈 수 있다.
- `All`은 selection row가 없는 기본값이다. role 또는 saved 선택은 singleton에 저장해
  재실행 뒤 복원한다. active saved Set 삭제는 FK cascade로 selection row도 제거해 All로
  fallback하며 rename은 stable Set ID 때문에 selection을 바꾸지 않는다.
- membership은 exact EventKit calendar identifier가 현재 source에 있을 때만 자동 resolve한다.
  snapshot title은 unavailable UI의 보조 표시값이지 자동 reconciliation 근거가 아니다.
  사라진 membership은 refresh와 available-calendar bulk update가 보존한다. 사용자가
  `Remove` 또는 replacement calendar를 명시적으로 고른 CAS rebind에서만 제거·변경한다.
  loading, permission denied, disconnected, fetch failure는 authoritative missing 판정이
  아니며 권한 있는 loaded 또는 authoritative-empty calendar snapshot에서만 unavailable로
  표시한다.
- 표시 event는 `global display enable ∩ selected Set`으로 계산한다. saved membership은
  global disable로 삭제되지 않으며 다시 enable하면 원래 Set에서 재표시된다. availability
  blocking은 global enable, active Set과 membership을 사용하지 않고 raw event에서 계산한다.
- Set filter는 Day/Week/Agenda와 같은 display projection만 좁힌다. raw EventKit fetch,
  Event Brief observation·identity·recovery, duplicate review와 editor destination은 줄이지
  않는다. duplicate/relink 대상 탐색과 성공한 원본 write의 focus 대상이 normal filter 밖일
  때는 persisted selection을 All로 바꾸지 않고 temporary reveal/bypass를 사용한다. 이미
  normally visible한 event에는 temporary state를 만들지 않는다.
- Settings는 create/rename/delete/reorder, account별 membership checkbox와 explicit
  unavailable replacement/removal을 제공한다. Set 이름·membership·선택은 KaosCal SQLite
  backup/reset 대상이고 EventKit calendar/event를 쓰지 않는다.

## 결과

사용자는 `All Calendars`, role 기반 Smart Filter와 이름 있는 exact calendar 조합을 서로
다른 개념으로 사용할 수 있다. overlapping membership과 mixed-role Set을 표현하면서도
global display enable 및 availability blocking의 기존 의미를 유지한다.

v9가 적용된 backup은 manifest migration ledger와 SQLite schema가 v9와 정확히 같을 때만
import할 수 있다. v8 이하 backup의 자동 migration, identifier 이름 추측, Set cloud/device
sync와 time/location 자동 전환은 제공하지 않는다.
