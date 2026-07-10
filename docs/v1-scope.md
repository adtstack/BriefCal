# V1 Scope

> 상태: Accepted
> 마지막 갱신: 2026-07-10
> 우선순위: 이 문서는 이전 문서와 충돌할 때 최신 ADR을 따라 해석한다.

## 한 줄 제품 정의

KaosCal은 macOS Calendar의 일정을 Day, Week, Agenda에서 관리하고, 일정 맥락과 개인 할 일을 로컬 Task Center에서 함께 처리하는 macOS-first calendar다.

## v1 필수 범위

| 영역 | 제공 범위 | 인수 기준 |
| --- | --- | --- |
| 플랫폼 | macOS 14 이상, Apple Silicon 우선 | Xcode에서 빌드·실행하고 권한 상태를 안전하게 처리한다. |
| 캘린더 연결 | macOS Calendar에 구성된 Exchange Online 계정을 EventKit으로 사용 | 별도 Microsoft OAuth/Graph 없이 Exchange source와 calendar를 읽는다. |
| 화면 | Day, Week, Agenda, mini month, 3-pane inspector | 같은 이벤트가 세 화면에서 같은 시간·출처·편집 가능 상태로 보인다. |
| 일정 | 시간 일정, 종일 일정, 시간대가 있는 일정과 floating 일정 | 종일은 날짜 범위로, 시간 일정은 시간대 의미를 잃지 않고 표시·편집한다. |
| 반복 | 모든 occurrence 표시, 기본 일·주·월·년 규칙 생성/편집, 이번 일정·이번 이후 범위 선택 | 반복 Brief가 다른 occurrence에 섞이지 않고, 서버가 거부한 변경은 원본을 훼손하지 않는다. |
| Event Brief | Before/During/After 작업, 로컬 메모, 변경 이력 | EventKit notes를 변경하지 않고 앱 재실행 뒤에도 유지된다. |
| Task Center | 이벤트 작업을 모아 보고, 이벤트에 연결되지 않은 가벼운 개인 작업을 추가 | 오늘·예정·완료 목록에서 작업 출처와 연결 일정을 명확히 보여 준다. |
| 안전성 | read-only 구분, 이동 확인, orphan 보존, 백업/복원 | 원본 일정과 KaosCal 데이터의 삭제·복원이 서로 영향을 주지 않는다. |

현재 구현 단계는 범위 자체와 구분한다. Phase 3까지 Day/Week/Agenda 읽기·표시와 로컬 Event Brief/event task/personal task 저장·조회 기반이 구현되어 있다. Event Brief와 Task Center의 실제 편집 UI는 Phase 4, 원본 일정 생성·편집·삭제와 시간대 변경은 Phase 5, 반복 변경 범위와 change log는 Phase 6에서 구현·검증한다.

## Exchange 지원 경계

- 지원 문구는 **“macOS Calendar에 구성된 Exchange Online 캘린더”**로 한정한다.
- 수정 가능 여부는 계정 종류가 아니라 EventKit이 보고하는 캘린더별 권한을 따른다.
- 온프레미스 Exchange는 별도 호환성 검증 전까지 지원을 약속하지 않는다.
- KaosCal은 Microsoft Graph, EWS, 자체 동기화 엔진, 계정 자격 증명을 사용하지 않는다.

## 초대 일정 정책

초대받은 일정은 표시하고 로컬 Event Brief와 작업을 붙일 수 있다. 다만 v1에서는 RSVP, 참석자, 주최자, 원본 제목·시간·삭제 변경을 제공하지 않는다. 사용자는 Calendar.app에서 해당 동작을 수행한다.

## Task Center 정책

Task Center는 프로젝트 관리 도구가 아니다.

- Event task: 하나의 Event Brief에 연결된 Before/During/After 작업
- Personal task: 일정 없이 빠르게 적는 개인 작업
- 제공하지 않는 것: 프로젝트, 팀 공유, Kanban, 우선순위 매트릭스, Apple Reminders·Exchange Tasks 동기화

## 명시적 제외 범위

- AI 자동 스케줄링, 자동 재배치, 자동 수락
- 모바일 앱, 서버 기반 KaosCal Cloud, 사용자 계정
- 직접 Google/Microsoft/CalDAV 동기화
- 초대 일정 RSVP·참석자 관리
- 복잡한 반복 규칙을 KaosCal이 안전하게 표현할 수 없을 때의 강제 수정

## 범위 변경 규칙

새 기능이 필요하면 먼저 다음을 확인한다.

1. Day/Week/Agenda, Event Brief, Task Center 중 하나를 더 신뢰성 있게 만드는가?
2. Exchange/EventKit의 실제 동작을 호환성 문서로 검증할 수 있는가?
3. 원본 일정과 로컬 데이터의 소유권 경계를 유지하는가?
4. ADR, QA, 구현 로그를 같은 변경에서 갱신했는가?
