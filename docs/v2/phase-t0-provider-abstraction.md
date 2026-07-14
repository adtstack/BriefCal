# T0 — Provider abstraction

> 상태: implemented / live pending
> 선행: v1 동결
> 다음 단계: [T1 Apple Reminders](phase-t1-apple-reminders.md)

## 목표

외부 task provider를 하나도 연결하지 않은 상태에서도 v1의 local-only 기능이 동일하게
동작하도록 유지하면서, 여러 provider를 추가할 공통 경계·계정·연결·동기화 상태를
도입한다. T0에서 실제 OAuth나 외부 서비스 write를 시작하지 않는다.

## 구현 checkpoint (2026-07-13)

- `v4_task_provider`를 additive migration으로 추가했다. 기존 local task 테이블은 유지하고,
  provider account/item, typed `task_bindings`, calendar destination만 별도 저장한다.
- `TaskProviding` 경계와 capability/auth/sync 상태 모델, `TaskProviderRepository`를 추가했다.
- destination이 없거나 provider 권한이 없으면 기존 local-only 경로를 유지한다.
- v1 backup ZIP은 migration/schema exact-match 정책 때문에 v2가 자동 복원하지 않는다. 현재는
  v2 current schema export만 허용하며 legacy importer는 후속 결정으로 남긴다.
- 전체 자동 회귀: 220 executed / 219 passed / 1 intentional manual-only skip / 0 failures.
- T1 Reminders adapter는 이 경계를 검증하기 위해 함께 staged했지만, 아래 fake/live gate가
  끝나기 전에는 외부 beta 기능으로 선언하지 않는다.

자동 contract/fake provider와 실제 provider fixture는 아직 live gate이므로 T0는 `live pending`으로
유지한다.

## 범위

- `TaskProvider` capability와 `TaskProviderRegistry` 정의
- provider account, remote item, item link, cursor의 additive 모델 검토·migration
- 캘린더별 destination 설정의 domain model과 local-only fallback
- local task와 remote task를 동일한 Task Center projection으로 표현
- 기존 `event_tasks`/`personal_tasks`와 remote item을 잇는 typed binding
- pending mutation, missing, conflict, disconnected 상태 모델
- fake provider 기반 contract test와 기존 local-only 전체 회귀

제외 범위는 OAuth, Keychain 실제 연결, 외부 task 생성, webhook, 직접 Calendar API다.

## 제안 경계

```swift
protocol TaskProvider {
    var descriptor: TaskProviderDescriptor { get }
    func authorizationState() async -> ProviderAuthorizationState
    func capabilities(for account: ProviderAccountRef) async throws -> TaskCapabilities
    func lists(account: ProviderAccountRef) async throws -> [RemoteTaskList]
    func create(_ draft: RemoteTaskDraft) async throws -> RemoteTask
    func update(_ task: RemoteTask, with patch: RemoteTaskPatch) async throws -> RemoteTask
    func delete(_ task: RemoteTask, expectedVersion: String?) async throws
    func sync(_ request: ProviderSyncRequest) async throws -> ProviderSyncResult
}
```

provider가 지원하지 않는 기능은 `TaskCapabilities`에서 명시한다. capability가
`relativeDue`, `timeZone`, `checklist`, `recurrence`, `deepLink` 중 하나라도 요구 의미를
보존하지 못하면 자동 연결하지 않고 local-only로 둔다.

## 데이터 설계 작업

1. 기존 local task ID와 remote task ID를 타입으로 분리한다. UI 문자열을 mutation key로
   사용하지 않는다.
2. `provider_accounts`에 provider 종류와 stable account key를 저장한다. 이메일을
   primary key로 사용하지 않고 display name과 별도로 둔다.
3. `provider_items`에는 최소 cache와 remote version만 보관한다. 원격 본문을 저장할지,
   저장한다면 어느 필드까지인지 capability와 privacy review를 거친다.
4. `item_links`에는 context, event occurrence, section, relation, sync state,
   last-synced hash를 저장한다.
5. `sync_cursors`는 provider/account/resource별 opaque 값으로 취급한다. cursor의
   내부 형식을 해석하거나 로그에 그대로 남기지 않는다.
6. `calendar_task_destinations`는 calendar/account scope, provider account, list/project,
   enabled, fallback 정책을 저장한다. 설정이 없으면 local-only가 기본이다.

`item_links` 또는 별도 `task_bindings`에는 `event_task_id`와 `personal_task_id` 중 정확히
하나를 저장한다. `context_id + section`만 저장하면 같은 Before/During/After section의
여러 task를 구분할 수 없으므로 허용하지 않는다. binding에는 provider item ID, account/list
scope, remote version, sync state와 마지막 hash를 둔다.

권장 초기 구조는 기존 `event_tasks`/`personal_tasks`를 local projection으로 유지하고,
provider 정본의 remote snapshot과 pending mutation을 별도 테이블로 두는 방식이다.
local-only row는 binding이 없으며 v1과 같은 repository 경로를 사용한다. 외부 provider
write가 성공한 뒤에만 local projection을 갱신하고, conflict에서는 local draft를 먼저
덮어쓰지 않는다.

모든 migration은 v1 DB를 열 수 있어야 하며, v1 backup을 v2에서 복원할지 여부는 별도
compatibility 결정으로 고정한다. 현재 backup은 migration 목록과 schema object를 exact
match하므로, v1 ZIP을 v2가 자동으로 import한다고 가정하지 않는다. legacy importer를
선택할 경우 staging DB에서만 migration하고 active DB는 preflight 전 교체하지 않는다.
token·secret·remote raw task 본문은 backup에 추가하지 않는다.

## 상태 규칙

- `localOnly`: provider가 없거나 사용자가 연결하지 않은 정상 상태
- `pendingCreate`, `pendingUpdate`, `pendingDelete`: 한 번만 실행 가능한 bounded mutation
- `linked`: remote ID와 account/list scope가 확인된 상태
- `missing`: remote deletion 또는 명시적 lookup 실패를 사용자에게 보여 주는 상태
- `conflict`: remote version과 local expected version이 어긋난 상태
- `disconnected`: token·권한·계정 문제로 sync가 중단된 상태

원격 삭제를 새 task로 자동 재생성하지 않는다. destination 변경이나 disconnect는 기존
remote task를 삭제하지 않고 local-only 또는 missing으로 전환할 수 있어야 한다.

## 구현 순서

1. domain enum/value type과 fake provider 작성
2. `TaskCenterItem` projection을 local/remote 양쪽 입력에 대해 정규화
3. migration과 repository를 추가하고 v1 local-only fixture를 재실행
4. destination Settings의 저장·읽기·삭제만 구현하고 provider 연결 버튼은 disabled 상태로 둠
5. pending/conflict/missing 상태의 UI copy와 `Needs attention` badge 추가
6. contract test, migration reopen, backup privacy 검사를 통과시킴

## 테스트·검증

- 기존 220개 suite 전부 통과, local-only task의 생성·완료·삭제·재실행 결과가 동일해야 함
- v1 DB를 v2 migration으로 열었을 때 기존 context/link/local task의 row와 의미가 보존되는지
- v1 current-schema ZIP을 v2에서 어떻게 처리하는지(legacy import 또는 명시적 거부) 테스트
- 같은 remote ID가 다른 account/list에서 충돌하지 않는지 검증
- 같은 event occurrence에 Before/During/After link를 잘못 합치지 않는지 검증
- create/update/delete 도중 process 재실행 시 무한 중복 mutation이 없는지 검증
- conflict에서 자동 덮어쓰기가 일어나지 않는지 검증
- 권한 없음·네트워크 오류·remote deletion을 서로 다른 상태로 표시
- export ZIP에 token, secret, remote raw body가 들어가지 않는지 검사
- Settings destination을 지워도 existing task와 원본 Calendar event가 삭제되지 않는지 검사

## 종료 게이트

T0는 다음 조건을 모두 만족할 때만 완료한다.

1. 외부 provider 없이 앱이 v1과 동일하게 빌드·테스트·기동된다.
2. migration reopen과 failed migration no-touch가 통과한다.
3. fake provider contract에서 state machine과 typed identity가 고정된다.
4. destination 없음/권한 없음은 local-only로 안전하게 fallback한다.
5. v1 DB 및 v1 backup compatibility 결정과 회귀 증거가 있다.
6. ADR, data model, QA checklist, known issues가 갱신된다.

이 중 하나라도 실패하면 T1의 실제 provider 작업을 시작하지 않는다.
