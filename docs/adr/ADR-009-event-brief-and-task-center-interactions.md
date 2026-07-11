# ADR-009: Event Brief와 Task Center 상호작용 안전성

> 상태: Accepted
> 날짜: 2026-07-10
> 관계: ADR-002, ADR-004, ADR-008을 구체화하며 대체하지 않음
> Phase 7A 확장: ADR-012가 completed context projection과 After Review를 추가함

## 배경

Event Brief와 Task Center는 같은 SQLite record를 서로 다른 화면에서 수정한다. 메모 자동 저장 중 일정이 바뀌거나, 편집 중인 task를 완료·이동하거나, 원본 일정 탐색과 기존 범위 fetch가 경쟁하면 사용자가 입력한 값이 사라지거나 다른 일정에 연결될 수 있다. 초대·read-only 일정에서는 원본과 local 편집 권한도 분리해 보여 줘야 한다.

## 결정

- `AppState`가 선택 일정, Event Brief load 상태, notes draft/save 상태, Task Center filter/query 상태와 recoverable local 오류를 한 곳에서 소유한다. 화면은 `selectedEventID`와 filter를 직접 바꾸지 않고 AppState 명령을 사용한다.
- 일정 선택은 local row를 만들지 않는다. 강한 identifier로 연결된 Brief만 불러오며 exact snapshot/fingerprint candidate 또는 ambiguous 결과에서는 편집을 막고 자동 relink·새 context 생성을 하지 않는다.
- notes는 입력 뒤 700ms debounce로 SQLite에 자동 저장한다. 일정 선택 변경, 다른 local mutation, scene inactive/background, 창 종료 알림 전에는 pending notes를 동기 flush한다.
- 같은 일정의 EventKit refresh는 pending draft를 DB snapshot으로 덮지 않는다. calendar fetch로 link가 갱신될 때 Brief snapshot과 Task Center due를 다시 읽되 draft와 save 상태는 보존한다.
- notes 저장 실패 시 현재 process 안에서 draft와 오류를 유지하고 Retry를 제공한다. 이 정책은 강제 종료까지 crash-safe임을 의미하지 않는다.
- event/personal task 생성은 Return 또는 Add에서 commit한다. 제목은 Return·focus loss에 저장하며 완료, section 이동, 원본 일정 열기 전에도 먼저 commit한다. 선행 저장이 실패하면 후속 동작을 중단한다.
- 완료 toggle은 즉시·가역적이고 이미 같은 완료 상태이면 `completed_at`을 덮어쓰지 않는다. 개별 local task 삭제는 확인 뒤 실행하며 원본 calendar event를 변경하지 않는다. notes는 비우기로 저장하고 전체 Brief 삭제는 Phase 4에 포함하지 않는다.
- Task Center mutation은 `TaskCenterItemID.eventTask(taskID:contextID:)`와 `.personalTask(taskID:)`로 라우팅한다. 표시용 문자열 ID를 parsing하지 않는다.
- Today는 미완료 overdue·오늘 due·due 없는 항목, Upcoming은 내일 이후 due, Completed는 완료 시각 역순이다. personal task due는 생성 뒤 수정·제거할 수 있고 현재 filter에 맞는 목록으로 이동한다. due는 분류·정렬 metadata이며 알림이나 Exchange task가 아니다.
- event task의 `due_kind = none`은 UI에서 “기한 없음”이 아니라 section 기본값으로 해석한다. Before/During은 원본 일정 시작, After는 원본 일정 종료를 따른다. fixed/relative due 저장은 지원하지만 Phase 4 UI에서는 section 기본값만 생성한다.
- event-linked row에는 task due와 별도로 section, 저장된 원본 일정 범위, calendar/source를 표시한다. 날짜 문자열은 AppState의 display calendar/time zone으로 만든다.
- 원본 일정 열기는 context의 저장 link에서 effective date range를 얻고 이전 pending range load를 취소한 뒤 target range를 fetch한다. 저장된 강한 identifier와 occurrence key가 정확히 하나와 맞을 때만 Day 화면에서 선택한다. weak/ambiguous/not-found이면 task를 보존하고 복구 가능한 오류만 표시한다.
- app active 복귀, calendar day 변경, system time-zone 변경과 EventKit refresh 뒤 Task Center를 다시 query한다.
- read-only calendar와 invitation의 원본 event control은 Phase 4에서 제공하지 않는다. 대신 `Calendar event · Read-only`/`Invitation · Original in Calendar.app`와 `Event Brief · Local editable`을 분리해 표시하며 local notes/tasks는 동일하게 편집할 수 있다.

## 결과

- Event Brief와 Task Center mutation 뒤 두 화면이 같은 DB 상태를 다시 읽는다.
- debounce 중 refresh나 완료·이동으로 notes/title draft를 잃지 않는다.
- event/personal task ID가 같아도 올바른 repository로 완료·삭제가 전달된다.
- 일정 이동 뒤 section 기본 due와 원본 일정 metadata가 새 snapshot을 따른다.
- Task Center는 Calendar 권한이 없어도 local 목록과 personal task를 사용할 수 있고, 원본 일정 열기만 full access를 요구한다.
- Phase 4에서는 EventKit write, RSVP, attendee 변경, 원본 일정 삭제, change log, relink UI를 만들지 않는다.

## 검토한 대안

- 전체 Brief의 명시적 Save 버튼: task 단위 transaction과 긴 notes 편집의 흐름이 달라 채택하지 않았다. notes만 debounce하고 task는 단위 commit한다.
- 모든 입력을 optimistic UI로 먼저 반영: 실패 시 rollback과 다른 화면 동기화가 불명확해 채택하지 않았다. mutation 성공 뒤 DB를 다시 읽는다.
- Task Center 표시 ID 문자열 parsing: event/personal namespace와 context 검증을 잃으므로 채택하지 않았다.
- weak fingerprint로 원본 일정 자동 선택: 비슷한 일정에 local data를 잘못 붙일 수 있어 채택하지 않았다.
- task due를 시스템 reminder로 예약: v1의 local 분류 범위를 넘고 권한·동기화 의미가 달라 채택하지 않았다.

## 남은 검증과 후속 범위

- 실제 서명 앱에서 notes 입력 직후 화면 전환·종료와 재실행 유지 확인
- 실제 `KAOS-TEST`에서 event-linked 원본 occurrence 탐색과 외부 이동 반영 확인
- read-only Viewer와 `KC-E6` invitation의 local-only 편집 실계정 확인
- event task fixed/relative due 편집 UI, notification/reminder, drag reorder는 후속 결정
- weak candidate relink, missing/orphan lifecycle은 Phase 6~7
- 원본 EventKit 생성·수정·삭제는 Phase 5
