# ADR-005: 결정·변경 기록 운영 규칙

> 상태: Accepted
> 날짜: 2026-07-10

## 결정

BriefCal에서 아래 중 하나가 바뀌면 코드 변경과 같은 작업 단위에 문서를 갱신한다.

- 사용자가 보는 동작, 화면, 문구, 권한 흐름
- 지원·제외 범위, 특히 Exchange 호환성
- 데이터 모델, migration, backup 형식
- 테스트·QA 기준과 알려진 위험
- 아키텍처 경계 또는 외부 의존성

## 필요한 기록

| 변화 | 반드시 갱신할 문서 |
| --- | --- |
| 제품 범위 | `v1-scope.md`, 관련 ADR |
| EventKit/Exchange 동작 | `exchange-compatibility.md`, QA, 구현 로그 |
| 데이터 모델 | `data-model.md`, 관련 ADR, migration test 기록 |
| 실제 구현 | `implementation-log.md`, phase plan, QA |
| 결정 교체 | 새 ADR, 기존 ADR 상태 |

## 결과

문서에 없는 결정은 임시 가정으로 취급한다. 검증하지 못한 항목은 지원 완료로 표시하지 않는다.

## 2026-07-12 현재 상태 기록 확장

구현이 여러 phase를 지나면서 README, setup, phase plan과 ADR header에 최신 test count와
live gate의 **요약 판정**이 중복되어 서로 다른 시점의 상태가 남는 문제가 생겼다. 이후
현재 phase, 최신 자동 suite와 열린 manual/live gate의 요약은 `docs/current-status.md`를
단일 기준으로 사용한다.

- `phase-plan.md`는 목표·Definition of Done과 phase별 구현 근거를 보존한다.
- `implementation-log.md`는 시간순 실행 기록을 보존하며 과거 결과를 최신 상태처럼 고치지 않는다.
- `exchange-compatibility.md`는 Exchange/EventKit 지원 판정의 상세 증거를 보존한다.
- phase plan·QA·implementation log·Exchange compatibility는 exact artifact/run과 역사적
  증거를 보존하되, README·developer setup과 ADR header는 이를 최신 요약처럼 복제하지
  않고 current status에 링크한다.

새 checkpoint에서는 current status와 implementation log를 함께 갱신하고, 지원 범위나 결정이
바뀐 경우에만 v1 scope·ADR·QA를 추가로 갱신한다.
