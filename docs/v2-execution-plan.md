# v2 실행계획

> 상태: T0·T1·T2·T3 implemented / live pending; T4 결정 완료; T5 reference-only implemented / live pending
> 기준일: 2026-07-14
> 선행 결정: [v1 동결 결정](v1-freeze.md)
> 제품 로드맵: [통합 캘린더·Task 로드맵](integrated-calendar-task-roadmap.md)

## 1. 목표

v2는 KaosCal을 “일정에 붙은 local task 앱”에서 “일정 중심 실행 허브”로 확장한다.
캘린더는 언제 하는지를, 외부 task provider는 무엇을 해야 하는지의 정본을 가진다.
KaosCal은 이 둘을 Before/During/After 의미와 안전한 연결 상태로 묶는다.

v2의 성공은 지원 provider 수가 아니라 다음 세 가지로 판정한다.

1. 사용자가 캘린더별 destination을 한 번 설정하면 새 task가 예측 가능한 곳에 생성된다.
2. local-only task와 외부 task가 한 Task Center에서 출처·계정·상태가 명확하다.
3. 삭제, 권한 철회, 네트워크 실패, 계정 재연결이 조용한 데이터 손실이 아니라 설명 가능한
   상태 전이로 나타난다.

## 2. 실행 순서

| 단계 | 이름 | 목적 | 의존성 | 종료 산출물 |
| --- | --- | --- | --- | --- |
| T0 | Provider abstraction | 외부 provider를 끼울 경계와 상태 모델 확정 | v1 동결 | local-only 회귀 + provider contract |
| T1 | Apple Reminders | native task provider 첫 실연동 | T0 | 실제 Reminders 양방향 완료 sync |
| T2 | Google Tasks + Todoist | OAuth provider와 destination 설정 일반화 | T0, T1의 상태 모델 | provider별 독립 gate |
| T3 | Microsoft To Do | M365/Exchange 사용자용 Graph task 연동 | T0, OAuth 계층, T2의 conflict 규칙 | delta sync + deep link |
| T4 | Direct Calendar APIs | EventKit 중복 수집 필요성의 조사·결정 | v1 호환성 자료, provider identity | 구현 여부 결정문 |
| T5 | Notes/reference | task와 참고자료를 분리한 최소 연결 | T0~T3 보안 경계 | URL/reference only 또는 명시적 보류 |

T4는 기본적으로 구현 단계가 아니라 **중복·정본·권한을 검증하는 의사결정 단계**다.
검증 결과가 충분하지 않으면 직접 Calendar API는 구현하지 않고 EventKit을 유지한다.
T5도 양방향 notes sync를 기본값으로 승격하지 않는다.

## 3. 공통 아키텍처 계약

### 3.1 정본

- Calendar event의 제목·시간·장소·참석자는 Calendar provider가 정본이다.
- 외부 task의 제목·본문·due·완료는 해당 task provider가 정본이다.
- Before/During/After, occurrence 관계, 연결 상태, fallback 정책은 KaosCal이 정본이다.
- 원격 데이터는 필요한 최소 캐시만 유지하며 캐시 삭제 후 재동기화가 가능해야 한다.

### 3.2 제안 additive 모델

T0에서 다음 모델을 검토하고 migration을 확정한다.

```text
provider_accounts  — provider, account key, display name, auth/capability state
provider_items     — remote entity, account/list, remote ID, version, minimal cache
item_links         — context, provider item, section, occurrence, sync state
sync_cursors       — account/resource별 opaque cursor와 갱신 시각
destinations       — calendar/account별 기본 provider와 list/project
```

기존 `event_contexts`, `event_links`, `event_tasks`, `personal_tasks`는 유지한다.
local-only task는 `provider_items` 없이도 동작해야 하며, 외부 task의 본문은 backup에
자동으로 복제하지 않는다.

v1의 `event_tasks`와 `personal_tasks`는 v2에서 즉시 삭제하거나 이름을 바꾸지 않는다.
외부 task를 연결할 때는 provider item과 기존 local task row 사이의 명시적 binding이
필요하다. `context_id + section`만으로 연결하지 않는다. 같은 section에 여러 task가
있을 수 있기 때문이다. T0에서 `event_task_id` 또는 `personal_task_id` 중 정확히 하나를
가리키는 binding 구조와 충돌 시 local/remote snapshot 보존 정책을 확정한다.

### 3.3 상태 전이

```text
local-only
  ├─ destination available → pending-create → linked
  ├─ unavailable           → local-only + Needs attention 없음
  └─ user disconnect        → local-only (원격 task 삭제 안 함)

linked
  ├─ local edit → pending-update → linked
  ├─ remote edit → refresh → linked
  ├─ version mismatch → conflict → user resolution
  ├─ remote delete → missing → explicit relink/unlink
  └─ auth/network error → pending/error → bounded retry + explanation
```

마지막 쓰기 우선으로 덮어쓰지 않는다. pending mutation은 무한 재시도하지 않으며,
재시도 횟수·마지막 오류·사용자 선택을 기록한다.

2026-07-17 구현은 `v10_task_provider_recovery`의 task별
`provider_pending_operations`와 `task_provider_preferences(local_only)`로 이 계약을
구체화했다. create/update/delete는 provider 호출 전에 pending을 남기고 명시적 retry를
3회로 제한한다. remote delete는 missing, 양쪽 projection 변경은 conflict이며, 사용자는
provider/account/list/task exact 후보를 골라 atomic relink하거나 원격 task를 보존한 채
task별 local-only로 전환할 수 있다. calendar destination 변경은 기존 binding을 이동하지
않고 그 시점의 unbound task를 local-only로 고정한다.

## 4. 공통 보안·개인정보 기준

- OAuth access/refresh token은 Keychain에만 저장한다.
- SQLite와 ZIP backup에는 token, client secret, 원격 provider 원문을 넣지 않는다.
- disconnect 시 token revoke를 시도하고, 연결 metadata/cache 삭제 여부를 사용자에게
  명확히 묻는다.
- provider 권한, 계정, list/project, 마지막 sync 시각과 오류를 Settings에서 확인한다.
- KaosCal notes 전체를 외부 task에 자동 복사하지 않는다.
- 로그에는 계정 이메일, raw remote ID, task 본문을 남기지 않는다.

## 5. 단계별 공통 완료 기준

각 단계는 아래 다섯 종류의 증거를 모두 갖춰야 완료로 표시한다.

1. 단위·통합 자동 테스트: fake provider, migration, conflict, retry, identity
2. 실제 provider fixture: 생성·수정·완료·삭제·재연결·권한 오류
3. 실제 UI: Settings destination, badge, error/recovery, keyboard 기본 흐름
4. 데이터 안전 audit: local-only 회귀, Calendar 원본 불변, backup token 부재
5. 문서: ADR, QA checklist, known issues, implementation log, provider compatibility

자동 테스트만 통과한 단계는 `implemented / live pending`으로 기록하고, 외부 beta
통과로 승격하지 않는다.

## 6. 세부 실행 문서

- [T0 Provider abstraction](v2/phase-t0-provider-abstraction.md)
- [T1 Apple Reminders](v2/phase-t1-apple-reminders.md)
- [T2 Google Tasks + Todoist](v2/phase-t2-google-tasks-todoist.md)
- [T3 Microsoft To Do](v2/phase-t3-microsoft-to-do.md)
- [T4 Direct Calendar APIs](v2/phase-t4-direct-calendar-apis.md)
- [T5 Notes / reference](v2/phase-t5-notes-reference.md)

## 7. 첫 착수 순서

T0를 바로 구현하기 전에 다음 결정만 먼저 고정한다.

- v1의 기존 local task row를 v2에서 projection/cache로 유지할지, 별도 task intent와
  remote projection으로 분리할지
- 기존 `event_tasks`/`personal_tasks`와 `provider_items`를 연결하는 typed binding 방식
- T0 schema를 기존 v1 migration에 additive로 넣을지 별도 v2 migration으로 넣을지
- destination 변경 시 기존 remote task를 local-only로 전환할지 새 task부터 적용할지
- provider account 식별자를 이메일이 아닌 어떤 stable account key로 표현할지
- provider capability에서 due/timezone/checklist/recurrence 손실을 어떤 공통 타입으로 표시할지

이 중 첫 두 항목을 확정하기 전에는 기존 task repository를 provider-aware로 수정하지
않는다. 권장안은 v2 초기에는 기존 task row를 local projection으로 유지하고, provider
binding·remote version·pending mutation을 별도 additive 테이블에 두는 것이다. provider
write가 성공한 뒤에만 projection을 갱신하며, conflict에서는 local과 remote snapshot을
둘 다 보존한다.

### 3.4 v1 SQLite와 백업 호환성

현재 backup 검증은 `grdb_migrations`의 전체 목록과 현재 schema object가 정확히 같은지
확인한다. 따라서 v2 migration을 추가하면 v1에서 만든 current-schema ZIP을 v2가 자동으로
그대로 import할 수 있다고 가정하면 안 된다.

T0에서 다음 중 하나를 명시적으로 선택한다.

1. v2가 격리된 staging DB에서 v1 archive를 검증·migration한 뒤 v2 current schema로
   변환하는 legacy importer를 제공한다.
2. v1 archive는 v1 build에서만 복원하고, v2는 새 export만 허용한다. 이 경우 사용자에게
   전환 전 export·보존 기간·복구 경로를 안내한다.
3. v1/v2가 공통으로 이해하는 별도 export format을 만들고, SQLite raw restore와 분리한다.

어느 선택이든 active DB를 preflight 전에 건드리지 않고, 실패 시 원본과 sidecar를 보존하며,
provider token과 원격 task 원문을 export하지 않아야 한다.

이 네 결정이 확정되면 T0의 fake provider와 local-only 회귀부터 구현한다. OAuth나
실제 provider 연결은 T0의 상태 모델과 안전성 테스트가 통과한 뒤에 시작한다.

## 8. 위험과 중단 기준

| 위험 | 중단 기준 | 대응 |
| --- | --- | --- |
| provider API 변경·폐기 | 공식 문서로 create/update/delete를 재현할 수 없음 | provider를 보류하고 reference-only로 낮춤 |
| 계정 중복 수집 | EventKit과 직접 API가 같은 event를 안전하게 식별하지 못함 | T4에서 직접 API 미구현 결정 |
| 원격 삭제 오판 | 삭제와 일시 권한/네트워크 오류를 구분할 수 없음 | 자동 삭제·재생성 금지, missing 상태 유지 |
| 토큰·본문 유출 | backup/log/diagnostic에 민감 값이 남음 | 해당 단계 gate 실패, release 차단 |
| provider별 의미 손실 | due/timezone/section mapping을 설명할 수 없음 | 자동 연결 금지, local-only fallback |

v2도 v1과 동일하게 “안전하게 확인할 수 없는 것은 자동 변경하지 않는다”를 최상위
원칙으로 유지한다.
