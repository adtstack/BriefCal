# ADR-005: 결정·변경 기록 운영 규칙

> 상태: Accepted
> 날짜: 2026-07-10

## 결정

KaosCal에서 아래 중 하나가 바뀌면 코드 변경과 같은 작업 단위에 문서를 갱신한다.

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
