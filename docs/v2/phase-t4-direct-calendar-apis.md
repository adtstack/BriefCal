# T4 — Direct Calendar APIs

> 상태: 완료 — EventKit 유지, direct Calendar API 보류
> 선행: v1 Exchange/EventKit 호환성 기록, T0 identity 모델, T2/T3 account 모델

## 목적

Google Calendar 또는 Microsoft Graph Calendar를 직접 연결해야 하는지 조사한다. Mac
EventKit이 이미 제공하는 일정과 직접 API 일정이 중복되는 순간 데이터 손실·중복 event·
서로 다른 권한 해석이 생길 수 있으므로, T4는 구현보다 “구현하지 않을 근거”도 같은
무게로 기록한다.

## 조사 질문

1. 현재 target 사용자에게 EventKit만으로 해결되지 않는 calendar 기능은 무엇인가?
2. 동일 계정·동일 event의 EventKit identifier와 direct API ID를 안정적으로 연결할 수 있는가?
3. 반복 occurrence, all-day, floating/zoned time, detached move를 두 source에서 같은
   occurrence key로 표현할 수 있는가?
4. direct API 권한이 EventKit 권한과 다를 때 사용자가 어느 source를 정본으로 인식하는가?
5. provider의 webhook/delta가 없어도 비용·지연·rate limit을 감당할 수 있는가?

## 비교 실험

각 후보 API에 대해 비민감 fixture로 다음을 실행한다.

- 동일 event create/update/delete와 source ID 수집
- 반복 series와 단일 occurrence, future split
- all-day·floating·time zone 이동
- Calendar.app/Exchange 외부 변경 뒤 양쪽 refresh
- remote deletion과 permission denied의 응답 구분
- 같은 계정을 EventKit과 direct API로 동시에 읽었을 때 duplicate 후보 생성

각 결과에는 provider, account type, exact build, fixture class, cleanup, residue를 남긴다.
실제 계정 이메일·raw ID·event 본문은 문서에 기록하지 않는다.

## 결정 규칙

다음 중 하나라도 만족하면 direct Calendar API를 구현하지 않는다.

- 동일 event를 안정적으로 deduplicate할 수 없음
- EventKit보다 더 안전한 occurrence identity를 제공하지 못함
- 권한·동기화 지연을 사용자에게 설명할 수 없음
- 기존 v1 기능과 별도 provider가 되어야 하는데 migration·support 비용이 과도함
- 공식 API·scope·rate limit이 장기적으로 불확실함

구현을 선택할 때에도 먼저 account별 `primaryCalendarProvider`를 하나만 허용하고,
secondary source는 read-only candidate로만 둔다. 한 event를 두 source에 자동 write하지
않는다.

## 산출물과 종료 게이트

- 후보별 capability/권한/identity/중복 비교표
- direct API를 구현하거나 보류하는 ADR
- 선택 시 T4 후속 구현 문서와 migration 계획
- 보류 시 “EventKit 유지”를 명시한 known issue와 다음 재검토 조건

T4는 비교표와 결정 ADR이 승인되기 전까지 코드 구현을 시작하지 않는다.

## 결정

[ADR-016](../adr/ADR-016-direct-calendar-api-deferral.md)에 따라 v2에서는 direct
Calendar API를 추가하지 않는다. 동일-event dedup fixture와 권한·occurrence 정본 증거가
없는 상태에서 두 source를 함께 읽거나 쓰는 것이 EventKit 단일 경계보다 안전하지 않다.
