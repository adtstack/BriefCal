# 통합 캘린더·Task 연동 계획

> 상태: Implemented baseline / live pending
> 마지막 갱신: 2026-07-20
> 적용 범위: KaosCal v1 이후의 v2+ 제품·기술 로드맵

이 문서는 v1 동결 뒤 provider 통합의 출발 결정과 목표를 보존한다. T0~T5와 Tasks 완성
트랙은 코드 기준 구현됐고 실제 계정·signed interaction은 대기 중이다. 현행 세부 계약은
[제품·시스템 스펙](specification.md), 최신 증거와 열린 gate는
[Current Status](current-status.md), 이후 상용 순서는
[상용 기능 로드맵](commercial-feature-roadmap.md)을 따른다.

현재 구현은 네 provider의 capability-aware 직접 CRUD, Apple 목록/account 이동과 Todoist
project/section 이동, local planning,
Event Brief 연결과 calendar time block까지 포함한다. AI, KaosCal Cloud, provider 간 자동
복제와 provider가 의미를 보존하지 못하는 반복/하위 작업 강제 변환은 포함하지 않는다.

## 1. 제품 방향

KaosCal을 여러 캘린더와 여러 Task 서비스의 데이터를 한 화면에서 연결하는 **일정 중심 실행 허브**로 확장한다.

- Calendar는 “언제 하는가”를 담당한다.
- Task provider는 “무엇을 해야 하는가”와 완료 상태를 담당한다.
- KaosCal은 일정과 task의 연결, Before/During/After 의미, 통합 보기와 안전한 동기화를 담당한다.
- Notes provider는 task와 별도의 참고 자료 계층으로 취급한다.

핵심 원칙은 모든 데이터를 KaosCal SQLite에 복제하는 것이 아니다. 각 외부 서비스가 task 또는 event의 정본(source of truth)이 되고, KaosCal은 연결 정보·동기화 상태·필요한 최소 캐시만 보관한다.

## 2. 제품 결정 요약

| 항목 | 결정 | 이유 |
| --- | --- | --- |
| Google Keep | 1차 범위에서 제외 | 현재 공개 Keep API는 일반 소비자용 notes 편집 API보다 Workspace 관리·감사 목적에 가깝다. |
| Todoist | 연동 후보로 채택 | 개인 task, 프로젝트, due, 완료, 증분 동기화와 webhook을 갖추어 Event Brief task와 잘 맞는다. |
| Apple Reminders | 최우선 | macOS native 접근이 가능하고 제목·due·완료 상태가 Before/During/After와 자연스럽게 매핑된다. |
| Google Tasks | 최우선 | Google 계정 사용자의 가벼운 task provider이며 공식 API가 있다. |
| Microsoft To Do | 최우선 | Exchange/Microsoft 365 사용자 기반과 맞고 Graph의 linked resource·delta query를 활용할 수 있다. |
| Google Calendar 직접 API | 후속 | Mac EventKit과 중복 수집을 피할 수 있을 때만 추가한다. |
| Notion | 선택적 후속 | task database로 사용할 수 있지만 범용 문서·프로젝트 도구라 핵심 Task Center와 경계가 흐려질 수 있다. |
| Jira/Linear/Asana 등 | 핵심 연동에서 제외 | 팀 프로젝트 관리가 주된 제품이라 KaosCal의 개인 일정 중심 범위를 크게 넓힌다. 우선은 링크 열기만 검토한다. |
| 외부 task 연결 방식 | 캘린더별 설정 + 자동 기본값 | task를 만들 때 provider를 고르지 않는다. 설정한 캘린더별 destination을 사용하고, 지원하지 않으면 local-only로 fallback한다. |

Todoist의 공식 API는 task·project·완료 이벤트를 제공하고, 현재 문서에는 webhook과 증분 동기화 경로가 안내되어 있다. 신규 구현은 deprecated Sync API v9가 아니라 Todoist API v1을 기준으로 한다. [Todoist API v1](https://developer.todoist.com/api/v1/)

Google Tasks API는 task list, task, 제목, notes, due, status, 위치 이동을 제공한다. [Google Tasks API](https://developers.google.com/workspace/tasks/reference/rest)

Microsoft Graph To Do API는 task list와 task를 제공하고, task에 원본으로 돌아가는 `linkedResource`를 저장할 수 있으며 task list에 대한 delta query를 지원한다. [Microsoft To Do API](https://learn.microsoft.com/en-us/graph/api/resources/todo-overview?view=graph-rest-1.0)

## 3. 목표 데이터 구조

```text
Calendar provider event
        │
        │ event_ref + occurrence_key
        ▼
KaosCal context / link
        │
        │ task_ref + section
        ▼
Task provider task
```

### 3.1 정본과 로컬 데이터의 소유권

| 데이터 | 정본 | KaosCal에 저장하는 것 |
| --- | --- | --- |
| event 제목·시간·장소·참석자 | Calendar provider | provider/account/remote ID, occurrence snapshot, 연결 context |
| task 제목·본문·due·완료 | Task provider | provider/account/list/task ID, 연결 section, sync fingerprint |
| Before/During/After 의미 | KaosCal | `section`과 occurrence 관계 |
| 연결 상태 | KaosCal | active, missing, detached, conflict, pending |
| 증분 동기화 위치 | 각 provider | sync token/cursor/etag 등 opaque metadata |
| OAuth token | Keychain 등 보안 저장소 | SQLite·backup에는 저장하지 않음 |

task 본문과 완료 상태는 외부 provider가 정본이다. KaosCal은 화면을 빠르게 표시하기 위한 최소 캐시를 둘 수 있지만, 캐시는 삭제 후 재동기화할 수 있어야 한다.

### 3.2 제안 모델

현재 `event_contexts`, `event_links`, `event_tasks` 모델을 바로 제거하지 않는다. 외부 provider를 추가할 때 다음 additive 모델을 먼저 도입한다.

```text
provider_accounts
- id
- provider
- account_key
- display_name
- authorization_state

provider_items
- id
- account_id
- entity_type: event | task | note
- remote_id
- remote_parent_id
- remote_version
- cached_title
- cached_due_at
- cached_completed
- last_seen_at

item_links
- id
- context_id
- event_task_id (nullable, mutually exclusive with personal_task_id)
- personal_task_id (nullable, mutually exclusive with event_task_id)
- provider_item_id
- section: before | during | after
- occurrence_key
- relation: event_task | reference
- sync_state
- last_synced_hash

sync_cursors
- account_id
- resource_kind
- cursor
- updated_at
```

`provider_items`와 `item_links`는 원격 데이터의 대체 저장소가 아니라 연결·복구·오프라인 표시를 위한 로컬 인덱스다. 외부 task를 사용하지 않는 기존 local-only task도 계속 지원한다.

## 4. 연결 방식: 캘린더별 기본 destination

task를 만들 때마다 provider를 고르게 하지 않는다. 사용자는 Settings에서 캘린더 또는 계정별 기본 task destination을 한 번 설정하고, Event Brief에서 새 task를 만들면 그 설정을 자동으로 사용한다.

기본 흐름은 다음과 같다.

```text
Settings에서 캘린더별 destination 설정
        │
        ├─ Apple/iCloud Calendar → Apple Reminders list
        ├─ Google Calendar       → Google Tasks list
        ├─ Exchange/Microsoft    → Microsoft To Do list
        ├─ 어떤 캘린더에도 매칭되지 않음 → Todoist (선택 설정)
        └─ 설정하지 않음/지원하지 않음 → KaosCal local-only
        │
Event Brief에서 task 생성
        │
설정된 destination에 자동 생성 또는 local-only fallback
```

Settings에서 사용자가 선택하는 항목은 다음과 같다.

- 캘린더·계정별 기본 provider
- 해당 provider의 기본 task list/project
- 외부 task 생성 활성화 여부
- 외부 provider가 unavailable일 때 local-only로 fallback할지

새 task 생성 화면에는 provider 선택 UI를 넣지 않는다. 대신 row에 `Reminders · 개인`, `Google Tasks · My Tasks`, `Todoist · Inbox`, `Local only` 같은 destination badge를 보여 준다. 고급 동작으로 기존 task의 destination 변경이나 외부 연결 해제를 제공할 수 있지만, 기본 흐름은 설정 중심으로 유지한다.

캘린더와 task provider가 같은 계정·제품군인지 자동으로 추측하지 않는다. 사용자가 계정을 연결하고 캘린더별 destination을 저장한 뒤, 실제 provider capability와 권한을 다시 확인해 사용한다.

Task Center row에는 다음 상태를 표시한다.

- `Local only`
- `Todoist · Inbox`
- `Reminders · 개인`
- `Google Tasks · My Tasks`
- `Microsoft To Do · Work`
- `Needs attention` — 권한·삭제·충돌 등으로 동기화되지 않음

provider가 특정 task 기능을 지원하지 않으면 연결 전에 capability를 보여 준다. 예를 들어 relative due, 시간대, checklist, recurrence 중 일부가 손실될 경우 자동 연결하지 않고 사용자가 확인하게 한다.

가능하면 provider의 원격 task에 KaosCal UUID를 되돌아오는 링크로 남긴다.

- Apple Reminders: `url`에 `kaoscal://task/<uuid>` 저장을 검토한다.
- Microsoft To Do: `linkedResource`에 KaosCal deep link를 저장한다.
- Todoist·Google Tasks: provider가 보존하는 URL/notes 필드가 있는 경우에만 marker를 저장하고, 원격 ID와 제목·due·event snapshot을 함께 사용해 재연결한다.

provider ID 하나만 영구 식별자로 믿지 않는다. 계정·list·occurrence·생성한 KaosCal UUID를 함께 보존하고, 원격 삭제는 자동 재생성하지 않고 `missing`으로 표시한 뒤 사용자가 재연결하도록 한다. Settings에서 destination을 local-only로 바꾸거나 연결을 해제하면 기존 KaosCal task를 삭제하지 않고 local-only로 전환한다.

## 5. 공급자별 1차 범위

### 5.1 Apple Reminders

macOS EventKit의 reminder entity를 사용한다.

- 별도 Reminders read/write 권한 요청
- 사용자가 대상 Reminder list 선택
- 해당 캘린더의 Settings destination이 Reminders로 설정된 새 task를 생성·이름 변경·due 변경·완료·삭제
- Reminders에서 바뀐 완료 상태를 KaosCal에 반영
- 연결 일정 열기 deep link
- source가 reminder를 지원하지 않거나 read-only이면 연결 차단

Calendar 권한과 Reminders 권한은 별개이며, 모든 EventKit source가 reminder calendar를 허용하는 것은 아니다. 따라서 캘린더 계정 이름만 보고 지원 여부를 추측하지 않고 실제 provider capability를 확인한다.

### 5.2 Google Tasks

- Google OAuth를 PKCE 기반으로 구현
- task list 선택
- 해당 캘린더의 Settings destination이 Google Tasks로 설정된 task의 제목·notes·due·status·position 단방향/양방향 sync
- 계정별 cursor와 마지막 동기화 시각 저장
- Google Tasks에서 삭제된 연결 task는 `missing` 처리

Google Calendar를 직접 API로 연결하는 단계와 Google Tasks 연결은 분리한다. Mac EventKit에 이미 등록된 Google Calendar를 다시 직접 가져오면 duplicate event가 생길 수 있기 때문이다.

### 5.3 Microsoft To Do / Exchange Tasks

“Exchange Tasks”를 별도 legacy 저장소로 추상화하기보다 Microsoft Graph To Do를 기본 경로로 삼는다.

- Microsoft OAuth와 delegated permission
- Settings에서 캘린더별 기본 task list 선택
- `linkedResource`로 KaosCal Event Brief deep link 연결
- due, reminder, importance, status, notes 매핑
- Graph delta query 기반 증분 동기화
- 조직 정책·scope·tenant 제한을 capability로 표시

Graph 계정과 macOS EventKit 계정이 같은 Microsoft 365 사서함을 가리키는 경우, 계정 연결 화면에서 중복 경로를 명시하고 한쪽을 primary로 선택하게 한다.

### 5.4 Todoist

Todoist는 개인 task provider 중 우선순위가 높다.

- OAuth 연결과 token revoke
- Settings에서 기본 Inbox/project/section 선택
- task 제목·description·due·완료·project를 Task Center에 표시
- Todoist API v1 webhook을 받을 수 있는 실행 환경이 있는 경우 webhook 사용
- webhook을 사용할 수 없는 local-only 배포에서는 provider 증분 조회와 주기적 refresh를 사용
- Todoist project 구조를 KaosCal의 project 기능으로 복제하지 않고 list 선택 정보로만 취급

KaosCal은 Todoist의 프로젝트·라벨·필터·팀 협업을 재현하지 않는다. Task Center에는 연결된 task와 출처만 보여 주고, 상세 프로젝트 관리는 Todoist로 연다.

## 6. 동기화와 충돌 규칙

### 6.1 기본 규칙

- Settings에서 destination을 지정한 캘린더의 새 Event Brief task는 해당 destination에 생성한다.
- destination이 없거나 provider capability·권한이 없으면 task는 local-only로 생성한다.
- 외부 provider 연결·계정·list/project 선택은 Settings에서 관리한다.
- 완료 toggle은 연결된 provider에 쓰고, 성공한 뒤 로컬 projection을 갱신한다.
- 외부 변경 알림은 즉시 fetch하지 못해도 다음 refresh에서 정합성을 회복한다.
- 원격 삭제는 local task를 조용히 지우지 않고 `missing` 또는 `unlinked`로 남긴다.
- 같은 task를 여러 provider에 자동 복제하지 않는다. 다중 destination은 향후 별도 기능으로만 검토한다.
- 네트워크 실패 시 pending mutation을 보관하되 무한 재시도하지 않는다.
- 충돌 시 마지막 쓰기 우선으로 덮어쓰지 않고 provider version과 local version을 비교해 사용자에게 선택지를 준다.

### 6.2 Before/During/After 매핑

| KaosCal section | 기본 due 의미 | 외부 task 표현 |
| --- | --- | --- |
| Before | event 시작 전 또는 시작 시각 | provider due/start time |
| During | event 시작 시각 또는 사용자가 지정한 due | provider due |
| After | event 종료 시각 또는 종료 후 | provider due/reminder |

provider가 시간대·부분 날짜·relative due를 충분히 지원하지 않으면 원래 의미를 잃지 않도록 KaosCal에서 capability를 표시하고, 자동 변환 대신 명시적 확인을 요구한다.

## 7. 보안·개인정보 경계

- OAuth access/refresh token은 Keychain에만 저장한다.
- token과 provider 원문은 KaosCal ZIP backup에 넣지 않는다.
- 원격 task 본문을 필요 이상으로 캐시하지 않는다.
- disconnect 시 token을 폐기하고, 사용자가 선택하면 연결 metadata와 cache도 삭제한다.
- provider별 권한과 동기화 범위를 Settings에서 확인할 수 있게 한다.
- 외부 provider에 KaosCal 내부 notes 전체를 자동 복사하지 않는다.

원격 task 연동은 로컬 SQLite 용량을 줄일 수 있지만, 계정·권한·동기화 상태를 관리하기 위한 로컬 DB가 여전히 필요하다. DB를 없애는 것이 아니라 **task 본문 중복을 줄이는 것**이 목표다.

## 8. 단계별 실행 계획

### Phase T0 — Provider abstraction

- `TaskProvider`와 `CalendarProvider` capability 정의
- provider account, remote item, link, sync cursor 모델 추가
- local-only task와 remote task를 동일한 Task Center projection으로 변환
- provider ID·occurrence·account scope 테스트

통과 기준: 기존 local task 기능이 그대로 유지되고, 외부 provider 없이도 앱이 동작한다.

### Phase T1 — Apple Reminders

- Reminders 권한·list 선택 Settings
- 캘린더별 기본 destination 설정 UI
- destination이 Reminders인 새 Event Brief task의 생성 및 양방향 완료 sync
- 삭제·재연결·권한 철회 처리
- 실제 iCloud/On My Mac fixture 검증

통과 기준: Settings에서 Reminders를 기본 destination으로 지정한 캘린더의 새 task만 Reminders에 생성된다. destination이 없거나 권한이 없으면 local-only로 남고, Reminders에서 완료한 연결 task는 KaosCal에 반영된다.

### Phase T2 — Google Tasks와 Todoist

- OAuth/Keychain 공통 계층
- Google Tasks adapter
- Todoist API v1 adapter
- 캘린더별 기본 provider/list를 관리하는 Settings UI
- provider별 due·완료·삭제·재연결 테스트
- destination badge와 fallback 상태 표시

통과 기준: 캘린더별 destination에 따라 새 task가 자동 생성되고, 설정하지 않은 캘린더의 task는 local-only로 생성된다. 출처·계정·list·Before/During/After가 혼동되지 않는다.

### Phase T3 — Microsoft To Do

- Microsoft Graph delegated auth
- linkedResource deep link
- delta query와 tenant/scope 오류 처리
- EventKit Exchange 경로와 Graph To Do 경로의 중복 경고

통과 기준: Graph To Do task에서 해당 KaosCal Event Brief로 돌아오고, 외부 완료/삭제가 안전하게 반영된다.

### Phase T4 — Direct Calendar APIs

- Google Calendar 직접 연결 필요성 검토
- Microsoft Graph Calendar 직접 연결 필요성 검토
- EventKit과 직접 API의 중복 event 방지 정책 확정
- provider별 sync cursor와 occurrence identity 통합

통과 기준: 동일 계정을 두 경로로 읽지 않고, 계정별 primary provider가 명확하다.

### Phase T5 — Optional notes/reference layer

- Google Keep은 일반 사용자 양방향 sync가 가능한 공식 API 범위가 확인될 때까지 보류
- Keep/Notion은 우선 note URL·reference attachment로만 지원
- notes를 task로 자동 변환하지 않음

## 9. 하지 않을 것

- Google Keep을 일반 소비자용 정식 양방향 task/notes 저장소로 약속하지 않는다.
- Todoist, Google Tasks, Reminders, To Do의 모든 프로젝트·라벨·협업 기능을 KaosCal에 복제하지 않는다.
- 같은 task를 provider 간 자동 복제해 중복 완료·중복 알림을 만들지 않는다.
- Jira/Linear/Asana를 핵심 화면에 넣어 프로젝트 관리 도구가 되지 않는다.
- token이나 원격 원문을 SQLite backup에 저장하지 않는다.

## 10. 성공 지표

- 캘린더별 destination을 설정한 뒤 생성한 Before/During/After task가 해당 외부 task 앱에서도 확인된다.
- local-only task와 외부 연결 task가 한 Task Center에서 명확히 구분된다.
- 어느 앱에서 완료해도 KaosCal의 Today/After Review가 일관되게 갱신된다.
- 원본 Calendar event의 notes·참석자·초대 상태를 오염시키지 않는다.
- 외부 task 삭제·권한 철회·계정 재연결 뒤에도 연결 상태를 설명할 수 있다.
- 여러 provider를 연결해도 Task Center에서 출처와 계정이 명확하다.
- 로컬 DB에는 task 본문을 불필요하게 중복 저장하지 않는다.

## 11. 결정 결과와 다음 gate

초기 결정은 다음처럼 닫혔다.

1. 첫 provider는 Apple Reminders로 구현했고 Google Tasks, Todoist, Microsoft To Do를 공통
   capability route에 추가했다.
2. Calendar event는 macOS EventKit을 유지하고 OAuth task 계정은 별도 source/account로
   표시한다. Google/Microsoft Calendar 직접 API는 중복 위험 때문에 구현하지 않는다.
3. calendar별 destination 변경은 기존 binding을 자동 이동하지 않고 변경 뒤 새 task에만
   적용한다. 기존 unbound task도 명시적 연결 전에는 local-only로 유지한다.

다음 gate는 새 provider 설계가 아니라 실제 네 provider 계정의 CRUD·permission·conflict,
Apple 계정 간 move/Undo, calendar drag 부분 성공, residue 0와 signed keyboard·VoiceOver다.
