# KaosCal Docs

KaosCal 문서는 제품 판단, 기술 결정, 구현 단계, QA 기준을 한곳에 남기는 공간이다.
앱 구현 전에 문서가 너무 커지지 않도록, v1 핵심 데모에 직접 필요한 문서부터 작성한다.

## 핵심 문서

1. [product-principles.md](product-principles.md)
   - KaosCal이 무엇을 하고 무엇을 하지 않는지 고정한다.
   - AI 자동 스케줄링, 팀 스케줄링, 전체 투두 앱으로 범위가 커지는 것을 막는다.

2. [architecture.md](architecture.md)
   - SwiftUI, EventKit, SQLite/GRDB, local-first 저장 원칙을 정리한다.
   - 원본 캘린더 이벤트와 KaosCal Event Brief 데이터를 분리하는 구조를 설명한다.

3. [phase-plan.md](phase-plan.md)
   - Phase 0부터 Phase 10까지의 개발 순서와 Definition of Done을 관리한다.
   - 각 단계가 빌드 가능한 작은 산출물로 끝나도록 한다.

4. [data-model.md](data-model.md)
   - event_contexts, event_links, event_tasks, event_change_log 등 로컬 DB 모델을 정의한다.
   - EventKit 식별자가 바뀌는 경우를 대비한 identity resolution 전략을 포함한다.

5. [qa-checklist.md](qa-checklist.md)
   - 권한 상태, Event Brief 저장, notes 오염 방지, 일정 이동, orphaned context를 검증한다.
   - 베타 배포 전 수동 테스트와 회귀 테스트 기준으로 사용한다.

## 이후에 필요할 문서

- [eventkit-decisions.md](eventkit-decisions.md): EventKit 권한, 읽기 전용 캘린더, 반복 일정 제한, 변경 알림 처리 결정
- [backup-restore.md](backup-restore.md): 로컬 DB export/import, 충돌 처리, 데이터 삭제 정책
- [distribution.md](distribution.md): 직접 배포, notarization, 라이선스, 베타 릴리즈 체크리스트
- [design-system.md](design-system.md): Calm Pro Calendar 톤, 3-pane layout, event card, source badge 규칙
