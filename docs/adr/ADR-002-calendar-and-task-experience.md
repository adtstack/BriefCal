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
