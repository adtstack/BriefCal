# Architecture Decision Records

ADR은 제품·기술·데이터 안전성에 영향을 주는 결정을 변경 이력과 함께 보존한다.

## 운영 규칙

- Accepted ADR은 과거 내용을 조용히 고쳐 쓰지 않는다.
- 결정이 바뀌면 새 ADR을 만들고 기존 ADR의 상태를 `Superseded by ADR-xxx`로 바꾼다.
- 구현 변경에는 관련 ADR, [v1 scope](../v1-scope.md), QA, [implementation log](../implementation-log.md)를 함께 갱신한다.
- 실제 Exchange 동작은 ADR의 가정이 아니라 [compatibility matrix](../exchange-compatibility.md)의 검증 결과로 판단한다.

## 색인

| ADR | 상태 | 제목 |
| --- | --- | --- |
| [ADR-001](ADR-001-platform-and-exchange.md) | Accepted | macOS 14+와 Exchange/EventKit 경계 |
| [ADR-002](ADR-002-calendar-and-task-experience.md) | Accepted | Day·Week·Agenda와 Task Center |
| [ADR-003](ADR-003-all-day-time-zone-and-recurrence.md) | Accepted | 종일·시간대·반복 일정 의미 |
| [ADR-004](ADR-004-invitation-and-identity-safety.md) | Accepted | 초대 일정과 Event Brief 연결 안전성 |
| [ADR-005](ADR-005-decision-and-change-recording.md) | Accepted | 결정·변경 기록 운영 규칙 |
| [ADR-006](ADR-006-native-project-build-baseline.md) | Accepted | 네이티브 프로젝트·빌드·보안 기준 |
| [ADR-007](ADR-007-calendar-layout-and-display-time.md) | Accepted | 캘린더 배치와 표시 시간 의미 |
| [ADR-008](ADR-008-local-context-store-and-event-identity.md) | Accepted | 로컬 Context 저장소와 이벤트 연결 안전성 |
| [ADR-009](ADR-009-event-brief-and-task-center-interactions.md) | Accepted | Event Brief와 Task Center 상호작용 안전성 |
| [ADR-010](ADR-010-original-event-write-safety.md) | Accepted | 원본 일정 쓰기와 로컬 Context 안전 경계 |
| [ADR-011](ADR-011-recurrence-move-change-log-and-session-undo.md) | Accepted | 반복 범위·안전한 이동·변경 기록과 세션 Undo |
| [ADR-012](ADR-012-lifecycle-after-review-and-orphan-confirmation.md) | Accepted | 시간 생명주기·After Review·orphan 확인 경계 |
