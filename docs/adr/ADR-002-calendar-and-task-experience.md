# ADR-002: Day·Week·Agenda와 Task Center

> 상태: Accepted
> 날짜: 2026-07-10

## 배경

KaosCal에는 모든 캘린더 관점과 눈에 보이는 할 일 목록이 필요하다. 기존 문서는 Event Brief 중심이었지만, 빠른 개인 작업의 위치가 없었다.

## 결정

- Day, Week, Agenda는 모두 v1 필수 화면이다.
- 세 화면은 공통 `DisplayEvent`와 시간 의미 모델을 사용한다.
- Task Center는 sidebar에서 열며 Event task와 Personal task를 한 목록으로 모은다.
- Personal task는 단순 제목·완료·기한을 가진 local-only 작업이다. 프로젝트·팀 공유·Kanban·Reminders sync는 제공하지 않는다.
- BusyCal의 정보 밀도와 3-pane 작업 흐름만 참고한다. KaosCal의 색·타이포그래피·아이콘·레이아웃은 독자적으로 만든다.

## 결과

- 오른쪽 Event Brief는 선택된 일정의 맥락을 담당한다.
- Task Center는 오늘·예정·완료를 보여 주고, event-linked task에는 원본 일정의 시간과 source를 표시한다.
- Month는 mini month로 시작하며, 전체 Month grid는 v1의 필수 화면이 아니다.

## 2026-07-11 mini month 구현 확장

- mini month는 Sidebar 상단의 고정 날짜 탐색기다. 전체 Month 화면, 이벤트 제목 배치, drag 생성·이동과 범위 선택을 제공하지 않는다.
- 현재 calendar의 `firstWeekday`, locale과 time zone을 사용하고 42개의 연속 civil day를 6×7로 고정해 월별 Sidebar 높이가 흔들리지 않게 한다. 날짜 증가는 86,400초가 아니라 calendar day 연산을 사용한다.
- 이전/다음 월 버튼은 mini month만 탐색한다. 날짜를 선택하면 display calendar의 시작 시각으로 정규화하고 Day/Week/Agenda는 현재 view를 유지한다. Task Center 또는 선택 없는 상태에서는 이동 결과가 보이도록 Day로 전환한다.
- toolbar Today와 날짜 선택처럼 focused date를 명시하는 action은 값이 기존 날짜와 같아도 local 월 탐색을 끝내고 그 날짜가 속한 월로 mini month를 다시 맞춘다.
- focused date는 accent fill, today는 ring, 인접 월 날짜는 낮은 강조도로 구분한다. 요일 header는 현재 주 시작 순서로 회전하고 날짜 button의 VoiceOver label에는 요일과 전체 날짜를 포함한다.
- 이벤트 dot은 현재 fetch가 42일 전체를 보장하지 않는 상태에서 거짓 `일정 없음` 인상을 줄 수 있으므로 넣지 않는다. 완전한 mini-month fetch coverage를 설계한 뒤 별도 확장한다.
