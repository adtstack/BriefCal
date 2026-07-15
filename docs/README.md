# KaosCal Docs

KaosCal 문서는 제품 판단, 기술 결정, 구현 단계, QA 기준과 실제 검증 결과를 남기는 기준 기록이다. 코드만 바꾸고 문서를 나중에 보완하지 않는다.

## 먼저 읽을 문서

1. [specification.md](specification.md)
   - 현행 제품·시스템 동작, 요구사항 ID와 인수 기준의 단일 스펙이다.

2. [current-status.md](current-status.md)
   - 현재 phase, 최신 검증 결과와 열린 manual/live gate의 단일 상태 기준이다.

3. [user-guide.md](user-guide.md)
   - 설치, 권한, 주요 기능, backup/reset과 사용자 데이터 경계를 설명한다.

4. [v1-scope.md](v1-scope.md)
   - 현재 v1의 필수·제외 범위와 Exchange 지원 경계를 정의한다.

5. [v1-freeze.md](v1-freeze.md)
   - v1 기능 개발 종료선, 유지보수 예외와 v2 전환 기준을 정의한다.

6. [v2-execution-plan.md](v2-execution-plan.md)
   - v1 이후 T0~T5 단계의 순서, 공통 계약과 완료 게이트를 정의한다.

7. [adr/README.md](adr/README.md)
   - Accepted 결정의 근거와 대체 이력을 관리한다.

8. [implementation-log.md](implementation-log.md)
   - 실제 변경, 검증 결과, 미해결 위험을 시간순으로 남긴다.

9. [developer-setup.md](developer-setup.md)
   - Xcode와 Exchange 테스트 환경 준비물을 정리한다.

10. [exchange-compatibility.md](exchange-compatibility.md)
   - 추측이 아닌 실계정 검증 결과로 Exchange 지원 범위를 선언한다.

## 제품·기술 기준 문서

- [product-principles.md](product-principles.md): 제품의 역할과 사용자 가치
- [architecture.md](architecture.md): SwiftUI, EventKit, SQLite/GRDB, local-first 경계
- [data-model.md](data-model.md): Event Brief, Task Center, identity lifecycle의 로컬 모델
- [eventkit-decisions.md](eventkit-decisions.md): 권한, read-only, 반복, 변경 알림의 구현 규칙
- [design-system.md](design-system.md): KaosCal 고유의 Calm Pro 3-pane UX
- [phase-plan.md](phase-plan.md): 빌드 가능한 작은 phase와 완료 기준
- [integrated-calendar-task-roadmap.md](integrated-calendar-task-roadmap.md): v2+ 다중 캘린더·Task provider 통합 로드맵
- [v2/README.md](v2/README.md): T0~T5 단계별 세부문서 인덱스
- [qa-checklist.md](qa-checklist.md): 회귀·수동·베타 검증 기준
- [backup-restore.md](backup-restore.md): 로컬 DB export/import와 복구 안전성
- [distribution.md](distribution.md): direct distribution, notarization, 라이선스 준비
- [known-issues.md](known-issues.md): 현재 제한, 미검증 범위와 안전한 우회
- [release-runbook.md](release-runbook.md): 버전·서명·notarization·패키징·철회 절차
- [phase10-blockers.md](phase10-blockers.md): 외부 beta 완료를 막는 입력·환경·미검증 gate

저장소 루트의 운영 문서:

- [CONTRIBUTING.md](../CONTRIBUTING.md): 개발 환경, 검증 명령과 변경 규칙
- [CHANGELOG.md](../CHANGELOG.md): 사용자 관점의 버전 변경 이력
- [PRIVACY.md](../PRIVACY.md): 로컬 데이터와 backup의 개인정보 경계
- [SECURITY.md](../SECURITY.md): 보안 가정과 취약점 보고 원칙
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md): 외부 의존성 고지
- [BETA-LICENSE.md](../BETA-LICENSE.md): 승인된 beta license/EULA로 교체하기 전 배포 중단선

## 문서 갱신 규칙

사용자에게 보이는 동작, 데이터 모델, 지원 범위, 테스트 결과가 바뀌면 같은 변경에서 관련
ADR·범위·QA·구현 로그를 함께 갱신한다. 현재 phase, 최신 test count와 열린 gate의 요약은
[current-status.md](current-status.md)를 기준으로 한다. QA·phase plan·implementation log와
Exchange compatibility에는 그 판정을 뒷받침하는 exact artifact, run과 역사적 증거를
보존한다. 상세 규칙은 [ADR-005](adr/ADR-005-decision-and-change-recording.md)에 있다.
