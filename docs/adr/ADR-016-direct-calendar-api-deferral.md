# ADR-016: 직접 Calendar API는 보류하고 EventKit을 유지한다

> 상태: Accepted
> 날짜: 2026-07-14
> 관계: ADR-001, ADR-008, v2 T4

## 결정

Google Calendar API와 Microsoft Graph Calendar API를 BriefCal의 추가 calendar source로
도입하지 않는다. v2에서는 macOS EventKit을 유일한 calendar read/write 경계로 유지한다.

## 근거

- EventKit과 direct API가 같은 계정의 동일 event를 제공할 때, stable identifier와
  recurrence occurrence를 손실 없이 교차 연결했다는 fixture 증거가 없다.
- 두 source를 동시에 읽으면 duplicate event, 서로 다른 권한 상태와 동기화 지연을
  사용자가 설명 가능한 하나의 정본으로 만들 수 없다.
- task provider OAuth는 task 연결에만 사용하며, Calendar event의 제목·시간·참석자·원본
  notes를 direct API가 변경하도록 확장하지 않는다.

## 결과와 재검토 조건

T4는 **보류로 완료**한다. EventKit이 해결하지 못하는 명확한 사용자 요구가 생기고,
비민감 fixture에서 single/recurring/detached/all-day/floating/time-zone/deletion/permission
및 EventKit 동시 읽기의 stable dedup을 모두 입증할 때만 별도 ADR로 재개한다. 재개 전에도
account별 primary calendar provider 하나만 write 가능하며 secondary는 read-only 후보로
제한한다.
