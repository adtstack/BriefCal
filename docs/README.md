# KaosCal Docs

KaosCal 문서는 제품 판단, 기술 결정, 구현 단계, QA 기준과 실제 검증 결과를 남기는 기준 기록이다. 코드만 바꾸고 문서를 나중에 보완하지 않는다.

## 먼저 읽을 문서

1. [v1-scope.md](v1-scope.md)
   - 현재 v1의 필수·제외 범위와 Exchange 지원 경계를 정의한다.

2. [adr/README.md](adr/README.md)
   - Accepted 결정의 근거와 대체 이력을 관리한다.

3. [implementation-log.md](implementation-log.md)
   - 실제 변경, 검증 결과, 미해결 위험을 시간순으로 남긴다.

4. [developer-setup.md](developer-setup.md)
   - Xcode와 Exchange 테스트 환경 준비물을 정리한다.

5. [exchange-compatibility.md](exchange-compatibility.md)
   - 추측이 아닌 실계정 검증 결과로 Exchange 지원 범위를 선언한다.

## 제품·기술 기준 문서

- [product-principles.md](product-principles.md): 제품의 역할과 사용자 가치
- [architecture.md](architecture.md): SwiftUI, EventKit, SQLite/GRDB, local-first 경계
- [data-model.md](data-model.md): Event Brief, Task Center, identity lifecycle의 로컬 모델
- [eventkit-decisions.md](eventkit-decisions.md): 권한, read-only, 반복, 변경 알림의 구현 규칙
- [design-system.md](design-system.md): KaosCal 고유의 Calm Pro 3-pane UX
- [phase-plan.md](phase-plan.md): 빌드 가능한 작은 phase와 완료 기준
- [qa-checklist.md](qa-checklist.md): 회귀·수동·베타 검증 기준
- [backup-restore.md](backup-restore.md): 로컬 DB export/import와 복구 안전성
- [distribution.md](distribution.md): direct distribution, notarization, 라이선스 준비

## 문서 갱신 규칙

사용자에게 보이는 동작, 데이터 모델, 지원 범위, 테스트 결과가 바뀌면 같은 변경에서 관련 ADR·범위·QA·구현 로그를 함께 갱신한다. 상세 규칙은 [ADR-005](adr/ADR-005-decision-and-change-recording.md)에 있다.
