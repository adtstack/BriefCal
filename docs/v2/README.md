# v2 단계 문서

v1은 [동결 결정](../v1-freeze.md)에 따라 종료한다. 이 디렉터리는 v2 이후 외부
provider·동기화·reference 기능을 단계별로 설계하고 검증하기 위한 문서 묶음이다.

전체 순서와 공통 계약은 [v2 실행계획](../v2-execution-plan.md)을 기준으로 한다.
각 문서는 코드를 바로 작성하기 위한 체크리스트가 아니라, 구현 전 결정·구현 범위·
테스트·live gate·중단 기준을 고정하는 단계별 인수 문서다.

| 문서 | 단계 | 완료 판단 |
| --- | --- | --- |
| [T0 Provider abstraction](phase-t0-provider-abstraction.md) | implemented / live pending | 외부 provider 없이 local-only 회귀 통과, fake/live gate 대기 |
| [T1 Apple Reminders](phase-t1-apple-reminders.md) | implemented / live pending | 실제 list의 생성·완료·삭제·재연결 gate 대기 |
| [T2 Google Tasks + Todoist](phase-t2-google-tasks-todoist.md) | implemented / live pending | provider별 독립 live gate 통과 |
| [T3 Microsoft To Do](phase-t3-microsoft-to-do.md) | implemented / live pending | delta·deep link·권한 오류 통과 |
| [T4 Direct Calendar APIs](phase-t4-direct-calendar-apis.md) | 완료 | EventKit 유지/직접 API 보류 ADR 확정 |
| [T5 Notes / reference](phase-t5-notes-reference.md) | implemented / live pending | reference-only UI와 privacy gate |

단계의 자동 테스트 통과만으로 `beta ready`를 선언하지 않는다. 문서에 적힌 실제
provider fixture와 cleanup이 없는 단계는 `implemented / live pending`이다.
