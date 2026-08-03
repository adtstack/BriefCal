# KaosCal 제품·시스템 스펙

> 상태: Living Specification
> 기준일: 2026-08-02, Asia/Seoul
> 기준선: v1 동결 범위, 구현된 v2 T0–T3, T4 결정, T5, saved Calendar Set,
> `v11_local_task_planning`, Full Month MVP, ADR-019 local-only 경계와 ADR-020 signed
> updater를 포함한 저장소 작업 트리
> 목적: 새 기능과 변경을 코드보다 먼저 합의하고, 구현·테스트·수동 검증을 같은 요구사항 ID로 추적한다.

## 1. 문서의 역할

이 문서는 KaosCal이 **무엇을 해야 하는지**와 그 동작을 **어떻게 인수할지**를 한곳에
정리한 현행 스펙이다. 제품 배경과 결정 이유를 모두 복제하지 않고 기존 정본을 연결한다.

- 이 문서: 사용자 동작, 시스템 불변식, 요구사항 ID, 인수 기준
- [Accepted ADR](adr/README.md): 결정 이유, 대안과 안전 경계
- [Architecture](architecture.md), [Data Model](data-model.md): 구현 구조와 저장 계약
- [Current Status](current-status.md): 최신 자동·live·Release 증거와 열린 gate
- [상용 기능 로드맵](commercial-feature-roadmap.md): 현재 기능 격차, C0~C4 순서와
  후속 `COM-*` 인수 기준
- [ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md): 이 Mac 단일 실행·저장,
  AI와 KaosCal Cloud 영구 제외, 허용되는 provider 직접 동기화 경계
- [ADR-020](adr/ADR-020-signed-automatic-updates.md): direct-download build의 서명된
  자동업데이트와 dormant 개발 빌드 경계
- [QA Checklist](qa-checklist.md): 수동 시나리오와 상세 판정 절차
- [Implementation Log](implementation-log.md): 실행한 명령, artifact와 시간순 결과

충돌이 있으면 더 최신인 Accepted ADR과 실행 증거를 우선하고, 같은 변경에서 이 문서를
갱신한다. 이 문서의 `구현` 표시는 코드 경계가 존재한다는 뜻이며, 실제 계정·실창·배포
검증까지 통과했다는 뜻은 아니다.

### 1.1 규범 용어

- **해야 한다**: 인수에 필수인 요구사항이다.
- **해서는 안 된다**: 안전·제품 경계를 위해 금지한다.
- **할 수 있다**: 선택 가능한 동작이다.
- **후속**: 현행 인수 범위가 아니며 별도 스펙 변경이 필요하다.

### 1.2 상태와 릴리스 경계

| 상태 | 의미 |
| --- | --- |
| `기준선` | v1 동결에 포함되고 구현된 현행 동작 |
| `구현 / live 대기` | 코드와 자동 계약은 있으나 실제 provider·Exchange·실창 gate가 남음 |
| `설계 승인 / 구현 대기` | 제품 동작과 인수 기준은 합의됐지만 코드와 자동 계약은 아직 없음 |
| `로드맵 승인 / 설계 대기` | 사용자 가치와 순서는 합의됐지만 세부 UX·capability·privacy 설계가 필요함 |
| `로드맵 승인 / ADR 대기` | 사용자 가치와 순서는 합의됐지만 write·데이터·권한 경계를 ADR로 결정해야 함 |
| `재평가 대기` | 선행 기능의 사용성·증거를 본 뒤 채택 여부와 순서를 다시 결정함 |
| `결정 완료` | 구현하지 않기로 한 경계까지 합의됨 |
| `제외` | 현행 제품에서 제공하지 않음 |

버전 경계는 다음과 같다.

- **v1 동결:** EventKit 캘린더, local Event Brief, local Task Center, 안전한 일정 변경,
  lifecycle/recovery, multi-calendar clarity, local backup/recovery
- **동결 후 구현:** 외부 task provider T0–T3, EventKit 유지 결정 T4, reference-only T5,
  calendar visibility와 availability blocking
- v1 동결 후 기능은 v1 제공 약속을 소급 변경하지 않는다.

## 2. 제품 계약

### 2.1 제품 정의

KaosCal은 macOS Calendar에 연결된 일정의 시간과 출처를 보여 주고 편집하면서, 각 일정의
준비·진행·후속 작업과 메모·참고 링크를 이 Mac에 오래 보존하는 macOS-only 실행 허브다.

### 2.2 핵심 사용자 결과

1. 사용자는 Day, Week, Month, Agenda에서 같은 일정을 같은 의미로 확인한다.
2. 일정이 이동·변경·삭제되어도 연결된 Event Brief를 조용히 잃지 않는다.
3. 원본 일정 변경 전에는 권한과 영향 범위를 이해하고 명시적으로 승인한다.
4. 일정 작업과 개인 작업을 Task Center에서 함께 보되 출처와 정본을 구분한다.
5. 캘린더별 표시 여부와 가용시간 차단 여부를 서로 독립적으로 정한다.
6. 외부 task provider를 연결하지 않거나 연결이 실패해도 local-only 흐름을 유지한다.
7. KaosCal 로컬 데이터는 사용자가 명시적으로 export/import/reset할 수 있다.

### 2.3 제품 원칙

- 사용자를 대신해 일정을 자동 결정·재배치·수락·삭제하지 않는다.
- 확인할 수 없는 identity, recurrence, 삭제 상태를 추측해 쓰지 않는다.
- Calendar 원본과 KaosCal 로컬 맥락의 소유권을 분리한다.
- read-only 원본에도 local Event Brief는 편집할 수 있게 한다.
- 출처, 역할, 권한, 연결 및 sync 상태를 숨기지 않는다.
- 서버·계정·구독 없이도 local-only 핵심 흐름이 동작해야 한다.
- KaosCal 기능과 KaosCal 소유 데이터는 이 Mac에서만 실행·저장하며 AI, KaosCal 계정,
  backend, cloud sync, telemetry와 remote automation을 도입하지 않는다.
- Calendar sync는 EventKit, task sync는 사용자가 선택한 provider와 이 Mac의 직접 연결로
  수행하며 KaosCal 중계 서버를 경유하지 않는다.
- 배포 update는 사용자 본문을 전송하지 않는 정적 HTTPS signed feed만 사용할 수 있고,
  구성·검증 실패가 local-only 핵심 흐름을 막아서는 안 된다.

## 3. 시스템 경계와 데이터 소유권

| 데이터 | 정본 | KaosCal 책임 |
| --- | --- | --- |
| 일정 제목·시간·장소·참석자·원본 notes | macOS EventKit의 Calendar event | 값 snapshot, 안전한 지원 범위의 read/write, 변경 후 재조회 |
| Before/During/After, KaosCal notes, lifecycle | KaosCal SQLite | 생성·보존·복구·backup |
| Personal task | KaosCal SQLite | local-only CRUD와 Task Center projection |
| 외부 task 제목·due·완료 | 선택한 task provider | 최소 local projection, binding, sync 상태와 충돌 설명 |
| calendar role·표시·blocking 정책 | KaosCal SQLite | EventKit 원본을 바꾸지 않는 sparse preference |
| 외부 reference | 외부 URL 대상 | URL·표시 제목·상태만 최소 저장 |
| OAuth credential | macOS Keychain | 연결·갱신·해제; SQLite/ZIP/log에 복제 금지 |

캘린더는 EventKit만 사용한다. Google Tasks, Todoist와 Microsoft To Do의 직접 API는
**task provider**이며 Calendar 원본 provider가 아니다.

## 4. 기능 요구사항

### 4.1 플랫폼, 권한과 조회

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `SYS-001` | 기준선 | macOS 14 이상 네이티브 앱으로 빌드·실행해야 한다. SwiftUI UI, EventKit calendar 경계, GRDB/SQLite local store를 사용한다. |
| `SYS-002` | 기준선 | KaosCal 기능과 KaosCal 소유 데이터는 이 Mac에서만 실행·저장해야 한다. AI SDK/API, KaosCal account/backend/cloud database, telemetry, remote config와 cross-device local-data sync를 추가해서는 안 된다. |
| `SYS-003` | 구현 / live 대기 | Calendar는 EventKit, 연결한 event task는 이 Mac과 사용자가 고른 provider 사이에서 직접 동기화해야 한다. KaosCal relay를 사용하면 안 되고 OAuth token은 Keychain에만 저장하며 provider가 없어도 local-only 흐름을 유지해야 한다. |
| `SYS-004` | 구현 / live 대기 | direct-download build는 유효한 HTTPS `SUFeedURL`과 32-byte Ed25519 공개 키가 모두 있을 때만 Sparkle updater를 시작해야 한다. 구성된 빌드는 자동 확인·설치와 수동 확인을 제공하고 signed appcast/archive 및 Developer ID/notarized app만 받아야 한다. 구성 없음, offline, feed 또는 서명 오류는 Calendar/Event Brief/task/local DB 동작을 막거나 데이터를 변경해서는 안 된다. 현재 ad-hoc GitHub prerelease는 update feed에 포함하면 안 되며 실제 이전-build upgrade는 별도 live gate다. |
| `CAL-001` | 기준선 | Calendar 권한을 `notDetermined`, `fullAccess`, `denied`, `restricted`, `writeOnly`, `unknown`으로 구분해야 한다. full access가 아니면 event fetch를 시작해서는 안 된다. |
| `CAL-002` | 기준선 | 첫 요청, 거부, 철회, 알 수 없는 미래 상태를 안전한 UI로 보여 줘야 한다. 권한 철회 시 메모리의 calendar/event/selection을 비워 이전 원본 정보가 남지 않아야 한다. |
| `CAL-003` | 기준선 | 시작 시 오늘 기준 -30일~+90일을 조회하고, 사용자가 범위를 벗어나면 visible interval 앞 30일·뒤 90일을 포함해 다시 조회해야 한다. |
| `CAL-004` | 기준선 | `EKEventStoreChanged`를 받으면 마지막 성공 범위를 다시 조회해야 한다. 연속 알림은 병합할 수 있으나, fetch에서 보이지 않는다는 이유만으로 원본 삭제를 확정해서는 안 된다. |
| `CAL-005` | 기준선 | `Reload events`와 `⌘R`은 현재 EventKit snapshot을 다시 읽어야 한다. Exchange 서버 동기화를 강제한다고 표현해서는 안 된다. |
| `CAL-006` | 기준선 | calendar source에는 calendar ID, source title, source identifier, account type, writable, color를 값 snapshot으로 제공해야 한다. 이름만으로 계정 identity를 만들면 안 된다. |
| `CAL-007` | 구현 / live 대기 | mini month는 표시 중인 6×7 grid의 42개 civil day 전체를 포함하는 event 조회가 성공한 뒤에만 일정 요약을 계산해야 한다. 월 탐색은 본문 focused date를 바꾸지 않으며, 추가 조회가 현재 본문 visible interval의 event snapshot을 유실하게 해서는 안 된다. 부분 조회·실패 상태를 `일정 없음`으로 표현해서는 안 된다. |

### 4.2 캘린더 화면과 시간 의미

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `UI-001` | 기준선 | Day, Week, Month, Agenda는 같은 `DisplayEvent` 의미·선택·Inspector 흐름을 공유해야 한다. Task Center는 별도 workspace section으로 열 수 있어야 한다. Month 고유 인수 기준은 `COM-003`을 따른다. |
| `UI-002` | 기준선 | Sidebar mini month는 고정 6×7 grid로 날짜를 선택하고, 선택 날짜에 맞춰 현재 calendar 화면을 이동해야 한다. |
| `UI-003` | 기준선 | timed event는 겹침을 최소 column으로 배치하고, 짧은 event의 최소 시각 높이와 자정 경계 multi-day 분할을 보장해야 한다. |
| `UI-004` | 기준선 | all-day/multi-day event는 배타 종료 날짜를 보존하면서 visible range에 clamp하고 재사용 가능한 lane에 배치해야 한다. |
| `UI-005` | 구현 / live 대기 | 완전한 `CAL-007` coverage가 있는 mini month는 일정이 하나 이상 겹치는 날짜의 숫자 아래에 단일 event dot을 표시해야 한다. dot은 숫자·focused fill·today ring과 겹치지 않아야 하며, focused date에서는 흰색, 일반 날짜에서는 accent, 인접 월에서는 낮은 opacity를 사용한다. 요약은 `global Enabled ∩ 선택 Calendar Set`을 적용하되 availability blocking과는 독립이어야 한다. timed multi-day와 all-day 일정은 배타 종료를 지켜 겹치는 모든 civil day에 반영한다. dot은 별도 hit target이 아니며 일정 수와 loading/unavailable 상태는 날짜 Button 또는 grid의 접근성 값으로 전달한다. |
| `TIME-001` | 기준선 | 시간 의미를 `allDay`, `floating`, `zoned`로 구분해야 한다. all-day는 날짜 범위, floating은 civil wall time, zoned는 시점과 zone 의미를 보존해야 한다. |
| `TIME-002` | 기준선 | all-day 종료는 배타 날짜로 저장하고 사용자에게는 포함 종료 날짜로 표시해야 한다. 자정에 끝나는 timed event가 하루를 더 차지하면 안 된다. |
| `TIME-003` | 기준선 | time zone 변경은 `현지 시각 유지`와 `동일 시점 유지`를 구분하고, DST gap/overlap의 존재하지 않거나 모호한 civil time을 자동 보정해서는 안 된다. |

### 4.3 Multi-calendar clarity와 가용시간

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `CFG-001` | 기준선 | calendar role은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`를 제공해야 한다. subscribed/birthdays만 Subscription으로 추론하고 나머지 account 용도는 추측하지 않는다. |
| `CFG-002` | 기준선 | 사용자가 명시한 role만 calendar identifier 기준 sparse row로 저장해야 한다. role 변경은 EventKit create/update/delete를 호출해서는 안 된다. |
| `CFG-003` | 구현 / live 대기 | Calendar Set selector는 synthetic `All Calendars`, role별 Smart Filter와 사용자 이름의 saved Set을 구분해야 한다. saved Set은 calendar identifier의 exact membership 조합이며 한 calendar가 서로 다른 role의 calendar와 함께 또는 여러 saved Set에 중복 포함될 수 있어야 한다. |
| `CFG-004` | 기준선 | 원본 write restriction은 invitation → attendee → subscribed → birthdays → provider read-only 순으로 결정해야 한다. 구체 ACL을 추측하지 않고 local Brief 편집 가능성을 함께 알려야 한다. |
| `CFG-005` | 기준선 | possible duplicate는 다른 calendar의 정규화 title과 보수적 시간 범위로 후보만 만들어야 한다. 자동 merge, hide, delete 또는 원본 write를 해서는 안 된다. |
| `CFG-006` | 구현 / live 대기 | calendar별 global display enable과 `blocksAvailability`를 독립 설정해 enable+block, enable+ignore, disable+block, disable+ignore를 모두 표현해야 한다. global disable은 saved membership을 지우지 않고 All, Smart Filter와 모든 saved Set에서 표시만 막아야 한다. |
| `CFG-007` | 구현 / live 대기 | 모든 calendar는 기본 visible이어야 한다. subscribed/birthdays는 기본 non-blocking, 나머지는 기본 blocking이며 read-only나 이름으로 기본값을 바꾸면 안 된다. |
| `CFG-008` | 구현 / live 대기 | visible event는 `global display enable ∩ selected Set`으로 계산해야 한다. 선택이 All이면 모든 enabled calendar, Smart Filter면 enabled calendar 중 해당 role, saved Set이면 enabled calendar 중 exact membership만 표시한다. raw fetch, Event Brief observation/recovery, duplicate review와 editor destination은 이 filter로 줄이면 안 된다. |
| `CFG-009` | 구현 / live 대기 | blocking은 raw event에서 별도로 계산해야 한다. free, canceled, current-user-declined는 제외하고 busy, tentative, unavailable, availability 미지원은 포함해야 한다. 숨긴 calendar도 block할 수 있어야 한다. |
| `CFG-010` | 구현 / live 대기 | 겹치거나 맞닿은 blocking interval은 union해야 한다. 같은 시간이 여러 calendar/event에 있어도 중복 가중하면 안 된다. |
| `CFG-011` | 구현 / live 대기 | Settings는 source identifier별 account group과 enable/block/role, account bulk action을 제공하고 별도 Calendar Sets pane에서 create/rename/delete/reorder, account별 membership checkbox, active Set 선택을 제공해야 한다. Sidebar는 Set 전환, global enable과 blocking 설명을 제공해야 하며 모든 변경은 local-only여야 한다. |
| `CFG-012` | 구현 / live 대기 | saved Set과 각 membership은 stable local ID로 저장하고 `(calendar_set_id, calendar_identifier)`를 중복 허용하지 않아야 한다. membership은 source/calendar snapshot을 보조 표시값으로 보존하되 exact calendar identifier만 자동 resolve해야 한다. |
| `CFG-013` | 구현 / live 대기 | 현재 source에서 사라진 membership은 bulk checkbox 갱신이나 refresh로 삭제하지 않아야 한다. 이름이 같다는 이유로 자동 연결하지 않고 Settings에서 사용자가 Remove 또는 명시적 Replace를 선택할 때만 제거·rebind해야 한다. loading·permission denied·fetch failure 같은 비권위 상태를 unavailable로 분류하면 안 되고, 권한 있는 loaded/authoritative-empty snapshot에서만 missing을 표시해야 한다. |
| `CFG-014` | 구현 / live 대기 | 선택한 role Smart Filter 또는 saved Set은 SQLite singleton으로 재실행 뒤 복원해야 한다. All은 selection row가 없는 기본값이고, active saved Set 삭제·누락·무효 selection은 All로 안전하게 fallback해야 한다. duplicate/relink 탐색과 성공한 원본 write 뒤 focus 대상이 normal filter 밖일 때만 저장 selection을 바꾸지 않는 temporary reveal을 사용해야 한다. |

### 4.4 원본 일정 생성·편집·삭제

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `EVT-001` | 기준선 | attendee 없는 writable calendar에서 단일 일정 create/update/delete를 지원해야 한다. 저장 전 최신 원본과 권한을 다시 확인하고 변경한 필드만 patch해야 한다. |
| `EVT-002` | 기준선 | invitation, attendee meeting, subscribed/birthdays, provider read-only event의 원본 write를 provider 호출 전에 차단해야 한다. local Brief는 계속 편집 가능해야 한다. |
| `EVT-003` | 기준선 | 기본 daily/weekly/monthly/yearly recurrence, interval, 종료, weekly weekdays를 손실 없이 표현 가능한 경우에만 생성·편집해야 한다. 복잡한 rule은 보존하고 강제 변환하면 안 된다. |
| `EVT-004` | 기준선 | 반복 occurrence update/delete는 `thisEvent` 또는 `futureEvents`의 명시적 scope를 요구해야 한다. scope 선택과 영향 확인 전에는 write하면 안 된다. |
| `EVT-005` | 기준선 | linked future-series write는 영향받는 모든 context의 strong reconciliation 계획이 없으면 차단해야 한다. detached occurrence의 future write도 차단한다. |
| `EVT-006` | 기준선 | calendar 이동, 시간 의미 변경, 반복 변경은 immutable impact preview와 Confirm을 거쳐야 한다. Cancel, validation failure와 no-op에는 EventKit write·change log가 없어야 한다. |
| `EVT-007` | 기준선 | linked write 성공 뒤 receipt의 strong identity로 기존 context를 rebind하고 change log를 같은 SQLite transaction에 기록해야 한다. EventKit 성공 뒤 local 실패는 부분 성공으로 알리고 자동 재시도·거짓 rollback을 하면 안 된다. |
| `EVT-008` | 기준선 | Undo는 같은 process session의 직전 linked nonrecurring single calendar/time mutation 한 건에만 허용해야 한다. recurrence, detached, details-only, delete, app 재실행 뒤에는 제공하지 않는다. |
| `EVT-009` | 기준선 | EventKit이 합성한 비반복 `occurrenceDate == startDate`를 반복 소속으로 해석하면 안 된다. 반복 판정은 recurrence rule 또는 detached membership으로 정규화해야 한다. |

### 4.5 Event Brief와 Task Center

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `CTX-001` | 기준선 | event 선택만으로 DB row를 만들면 안 된다. 첫 non-empty local notes 또는 event task 저장 시 context와 link를 한 transaction에서 만들어야 한다. |
| `CTX-002` | 기준선 | KaosCal notes는 EventKit notes와 분리해 SQLite에 저장하고 debounce 중 navigation·mutation 전 flush해야 한다. 실패 시 원본 editor를 열기 전에 사용자에게 알려야 한다. |
| `CTX-003` | 기준선 | Event task는 Before/During/After, ordering, completion, none/relative/fixed due를 지원해야 한다. 한 context의 task mutation이 다른 context row를 바꾸면 안 된다. |
| `CTX-004` | 기준선 | Event Brief에는 원본 source/role/write restriction, local notes/tasks, 변경 이력과 복구 상태를 구분해 보여 줘야 한다. |
| `TASK-001` | 기준선 | Personal task는 event 없이 생성·이름 변경·due 변경·완료·삭제할 수 있어야 하며 local-only여야 한다. |
| `TASK-002` | 구현 / live 대기 | Task Center는 event task와 personal task를 typed identity로 결합하고 Today, Upcoming, Overdue, No Date, After Review, Completed filter를 서로 겹치지 않게 제공해야 한다. raw 문자열 ID 충돌로 잘못된 task를 변경하면 안 된다. |
| `TASK-003` | 기준선 | completed context는 열린 After task만 Today/Upcoming/After Review에 투영해야 한다. 이 projection은 숨긴 task row를 삭제하거나 자동 완료하면 안 된다. |
| `TASK-004` | 기준선 | event task source를 열면 저장 link로 occurrence-aware lookup하고 strong match만 해당 event로 이동해야 한다. 일반 visible-range fetch 결과를 삭제 증거로 사용하면 안 된다. |
| `TASK-005` | 구현 / live 대기 | 오른쪽 `Tasks`는 Apple Reminders, Google Tasks, Todoist, Microsoft To Do의 list/project/section metadata를 source·account별로 보여 주고 `(provider, accountKey, listID)` exact identity로 선택해야 한다. 특정 list 선택 뒤 Open/Completed/All, 제목·설명 검색, due/priority/title 정렬을 조합하며 다른 list task를 섞으면 안 된다. 빈 list는 metadata로 보존하고 일시적 metadata 오류에는 loaded task fallback을 허용한다. 선택 list·상태·정렬은 화면 왕복과 재실행에 복원하되 loading 중에는 유지하고 authoritative 삭제 뒤 All로 돌아가야 한다. |
| `TASK-006` | 구현 / live 대기 | 오른쪽 `Tasks`의 writable provider 행은 exact `(provider, accountKey, listID, remoteTaskID)`와 원격 version으로 최신 task를 확인한 뒤 완료를 인라인 변경하고 생성·제목·notes·기한 설정/제거·완료·삭제를 목록 아래의 resizable detail drawer에서 수행해야 한다. drawer는 목록을 가리지 않고 선택 행을 유지하며 미저장 draft 전환도 내부에서 처리한다. Apple Reminders는 writable list/account 이동, Todoist는 같은 account의 project/section 이동, Apple/Microsoft/Todoist는 priority, Microsoft는 별도 reminder on/off와 시각도 지원한다. read-only 또는 metadata 확인 실패 목록은 조회만 허용하고 version mismatch는 draft를 보존한 conflict와 `Reload Latest`/`Cancel`만 제공해야 한다. 원격 notes와 일반 provider task는 local planning DB에 복제하지 않으며 연결 원격 삭제는 local Event Task를 missing/Needs attention으로 보존해야 한다. |
| `TASK-007` | 구현 / live 대기 | 오른쪽 `Tasks`는 명시적 선택 모드와 capability가 완료를 지원하는 writable 작업의 일괄 완료·미완료를 제공해야 한다. list move 일괄 작업은 provider가 안전한 move를 지원하는 같은 provider/account 범위로 제한한다. 단일·일괄 mutation은 마지막 성공 작업에 한해 process-local Undo를 제공하고, Undo 직전 최신 remote version이 달라졌으면 conflict로 중단해야 한다. 신뢰할 수 있는 원본 URL만 원본 열기에 사용하고 EventKit reminder의 사용자 URL을 Reminders deep link로 오인하면 안 된다. Syncing과 마지막 성공 조회/변경 시각을 표시하되 일반 remote notes를 저장하는 durable direct-edit queue나 영구 Undo를 암시하면 안 된다. |
| `TASK-008` | 구현 / live 대기 | local Event/Personal task는 중요 표시, none/low/medium/high priority, daily/weekly/monthly/yearly 반복 간격, 예상 시간, 실제 실행 timer와 checklist를 SQLite local planning overlay로 저장해야 한다. 반복 작업을 처음 완료하면 다음 occurrence와 미완료 checklist를 만들고 실제 시간은 0으로 초기화해야 한다. 이 overlay를 provider가 지원하지 않는 필드에 조용히 write하면 안 된다. |
| `TASK-009` | 구현 / live 대기 | 기존 provider task를 Event Brief task에 exact identity로 연결하고, provider task를 timed calendar canvas에 drop하면 15분 단위·기본 1시간 calendar block과 During task를 만들어 연결해야 한다. destination은 현재 Calendar Set의 writable calendar로 제한한다. Event task는 fixed 및 event start/end 기준 상대 기한을 편집할 수 있고 event 이동 뒤 연결 provider due를 다시 계산해야 한다. |
| `TASK-010` | 구현 / live 대기 | Task Center는 날짜 또는 list/source grouping, role filter, 이 Mac에만 저장하는 named views와 Calendar+Tasks 통합 검색을 제공해야 한다. 연결되지 않은 provider task도 같은 날짜 filter와 검색에 표시하되 이미 Event Task로 투영된 remote task를 중복 표시하면 안 된다. |
| `TASK-011` | 구현 / live 대기 | Event Task provider mutation은 SQLite pending queue, 최대 3회 명시적 Retry, cancel-and-local-only, last error와 재실행 복원을 제공해야 한다. 직접 provider task 편집은 remote notes를 SQLite에 저장하지 않는 경계를 우선해 실패한 sheet draft를 메모리에 보존하며 자동/무한 재시도하지 않는다. |

### 4.6 Lifecycle, missing/orphan과 원본 삭제

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `LCY-001` | 기준선 | context lifecycle은 scheduled, completed, cancelled, orphaned를 사용해야 한다. 시간 경과는 scheduled/completed만 갱신하고 cancelled/orphaned를 덮어쓰면 안 된다. |
| `LCY-002` | 기준선 | active link의 첫 사용자 명시 lookup `notFound`만 missing으로 만들고, missing 상태에서 사용자가 다시 Recheck해 `notFound`일 때만 orphan review를 열어야 한다. 오류·권한·ambiguous·inconclusive는 상태를 바꾸면 안 된다. |
| `LCY-003` | 기준선 | Keep as orphan, 검증된 Relink, Delete local Brief를 서로 다른 명령으로 제공해야 한다. Relink는 final provider verification과 expected-link CAS를 통과한 뒤 atomic rebind해야 한다. |
| `LCY-004` | 기준선 | missing/orphaned local Brief 삭제는 SQLite context만 cascade 삭제하고 EventKit delete를 호출해서는 안 된다. |
| `LCY-005` | 기준선 | linked original delete는 saved-link·notes·tasks impact review와 별도 final Confirm 뒤에만 실행해야 한다. 성공 뒤 local Brief/tasks는 보존하고 context cancelled + link orphaned + unavailable cancellation log로 finalize해야 한다. |
| `LCY-006` | 기준선 | `deleted original` 표시는 현재 link 세대의 KaosCal deletion provenance가 있을 때만 보여야 한다. 더 최신 relink는 과거 deletion provenance를 무효화해야 한다. |

### 4.7 외부 task provider

이 절의 구현은 모두 실제 provider fixture와 cleanup이 남아 있으므로 beta-ready가 아니다.

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `PRV-001` | 구현 / live 대기 | 공통 provider 경계는 authorization, capability, list, create/update/delete, refresh/change callback과 typed sync state를 제공해야 한다. provider가 없어도 v1 local-only 회귀가 없어야 한다. |
| `PRV-002` | 구현 / live 대기 | calendar별 destination은 provider+account+list의 복합 identity로 저장해야 한다. destination이 없거나 사용할 수 없으면 local-only fallback을 유지해야 한다. |
| `PRV-003` | 구현 / live 대기 | 외부 destination으로 mirror하는 대상은 Event Brief event task다. Personal task는 현행 release에서 local-only로 남아야 한다. |
| `PRV-004` | 구현 / live 대기 | Apple Reminders는 별도 full-access 권한, exact account/list/task identity, writable list, 제목/notes/due/완료/list move/delete, optimistic version conflict와 외부 변경 refresh를 지원해야 한다. 연결 task를 목록·계정 사이에서 이동할 때 durable binding도 같은 transaction에서 새 parent/account로 옮겨야 한다. 외부 삭제가 local task를 조용히 삭제하면 안 되며 원격 notes를 local DB·backup에 저장하면 안 된다. |
| `PRV-005` | 구현 / live 대기 | Google Tasks와 Todoist는 OAuth authorization code + PKCE, task list projection, 생성·조회·제목/notes/due·완료·삭제 mutation을 지원해야 한다. Todoist는 같은 account의 project/section 이동·Undo·priority·deep link와 최근 90일 completed archive projection을 지원하며, 완료와 field 편집을 함께 저장할 때 active field write를 close보다 먼저 수행해야 한다. Google의 date-only due·ETag 및 cross-list move 미지원 의미와 섞지 않아야 한다. |
| `PRV-006` | 구현 / live 대기 | Microsoft To Do는 tenant+account identity, list destination, ETag write, 생성·조회·제목/notes/due/priority/reminder·완료·삭제와 opaque delta cursor를 지원해야 한다. EventKit Exchange account와 Graph account를 이메일만으로 자동 병합하면 안 된다. |
| `PRV-007` | 구현 / live 대기 | OAuth token은 Keychain에만 저장하고 SQLite, ZIP, log에 넣으면 안 된다. Google Desktop client credential은 Git 밖의 `.env`/CI에서 빌드에 주입해 token·refresh request에만 사용하고 최종 사용자에게 입력받지 않는다. |
| `PRV-008` | 구현 / live 대기 | public client ID/redirect가 없는 build는 provider가 미구성임을 보여 주고 동작하지 않는 Connect 흐름을 열면 안 된다. registered callback이 필요한 provider는 그 배포 조건을 설명해야 한다. |
| `PRV-009` | 구현 / live 대기 | remote delete는 local task를 보존한 missing, version mismatch는 conflict, auth/network 문제는 설명 가능한 pending/error로 나타내야 한다. last-write-wins로 조용히 덮어쓰거나 무한 재시도하면 안 된다. |
| `PRV-010` | 결정 완료 | Google/Microsoft Calendar 직접 API는 구현하지 않고 Calendar 정본을 EventKit으로 유지해야 한다. task API를 calendar API 중복 수집의 근거로 사용하면 안 된다. |
| `PRV-011` | 구현 / live 대기 | Event Brief task는 provider/account/list/task exact 후보를 사용해 기존 remote task로 명시적으로 relink할 수 있어야 한다. task별 local-only unlink는 원격 task를 삭제하지 않고 재실행 뒤 유지돼야 하며, calendar destination 변경은 기존 binding이나 unbound task를 새 destination으로 조용히 이동·복제하면 안 된다. |

### 4.8 Reference-only 계층

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `REF-001` | 구현 / live 대기 | Event Brief는 HTTP/HTTPS reference URL, provider(web/notion), 표시 제목, 상태와 확인 시각만 저장해야 한다. |
| `REF-002` | 구현 / live 대기 | reference는 active, missing, permissionRequired, disconnected를 구분하고 task 또는 provider destination으로 자동 변환하면 안 된다. |
| `REF-003` | 구현 / live 대기 | 외부 문서 본문, 권한 모델과 양방향 notes sync는 현행 범위가 아니다. reference 삭제는 EventKit event나 외부 원문을 삭제해서는 안 된다. |

### 4.9 Local Data, backup과 bootstrap recovery

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `DATA-001` | 기준선 | local store는 Application Support의 SQLite를 사용하고 foreign key를 항상 활성화해야 한다. hosted test는 production DB를 열면 안 된다. |
| `DATA-002` | 기준선 | migration은 additive이며 이미 적용된 migration을 수정하면 안 된다. 현행 ledger는 `v1_context_store`부터 `v11_local_task_planning`까지 순서대로 적용한다. |
| `DATA-003` | 기준선 | EventKit ID 하나를 영구 identity로 간주하면 안 된다. strong IDs, calendar, recurrence/occurrence anchor, 시간 의미와 snapshot을 사용하고 weak/fingerprint 후보는 사용자 승인 전 자동 연결하면 안 된다. |
| `DATA-004` | 기준선 | role·calendar usage preference와 saved Set membership은 exact calendar identifier에만 적용한다. identifier churn 뒤 같은 title이라는 이유로 자동 이식하면 안 되며 saved membership rebind는 사용자의 명시적 선택과 stale-ID 검증을 요구해야 한다. |
| `BAK-001` | 기준선 | export는 store-only classic ZIP에 `kaoscal.sqlite`와 `manifest.json` 두 entry만 만들고 migration ledger, schema, byte count, SHA-256과 크기 상한을 검증 가능하게 기록해야 한다. |
| `BAK-002` | 기준선 | ZIP은 plaintext이며 서명·암호화 backup으로 표현하면 안 된다. credential/token, 전체 EventKit store와 외부 원문은 넣지 않되 사용자 notes/tasks와 linked snapshot에는 민감정보가 있을 수 있음을 알려야 한다. |
| `BAK-003` | 기준선 | import는 실행 중인 앱과 application ID·schema·migration이 정확히 같은 trusted backup만 허용해야 한다. preflight 전 active DB를 바꾸면 안 되고 record merge·schema upgrade/downgrade를 제공하면 안 된다. |
| `BAK-004` | 기준선 | import/reset은 먼저 recovery ZIP을 만든 뒤 같은 live writer에서 restore 또는 local-data reset을 수행해야 한다. 모든 경로는 EventKit write를 호출하면 안 된다. |
| `BAK-005` | 기준선 | reset은 KaosCal user-data table을 비우되 schema와 GRDB migration history를 유지해야 한다. provider metadata/cursor/binding/reference, role/usage와 saved Set/membership/selection도 현재 schema의 reset 대상에 포함한다. Keychain credential 삭제는 별도 Disconnect 확인 경계다. |
| `BAK-006` | 기준선 | bootstrap DB open/migration 실패 시 strict same-schema backup을 먼저 검증하고, 기존 SQLite family를 Recovery에 격리한 뒤 설치해야 한다. 설치 검증 실패 시 원본 family 전체 rollback을 시도해야 한다. |
| `BAK-007` | 기준선 | rollback 자체가 실패하면 해당 session의 mutation과 refresh를 quarantine하고 부분 복구를 성공으로 표시하면 안 된다. |

### 4.10 Onboarding, Settings와 사용자 안내

| ID | 상태 | 요구사항과 인수 기준 |
| --- | --- | --- |
| `SET-001` | 기준선 | 첫 실행은 이 Mac에만 저장되는 local-only 데이터 경계, Calendar full access와 선택 provider 직접 동기화 이유를 설명하고 사용자의 명시적 Continue 뒤 완료 상태를 저장해야 한다. |
| `SET-002` | 기준선 | Settings는 Calendars, Calendar Sets, Task Providers, Local Data의 책임을 분리해 제공해야 한다. destructive reset은 정확한 `RESET` 입력과 별도 확인 없이는 활성화하면 안 된다. |
| `SET-003` | 기준선 | permission recovery, empty state, operation error와 partial success는 사용자가 다음 안전한 행동을 알 수 있는 문구를 제공해야 한다. |
| `SET-004` | 구현 / live 대기 | Settings의 calendar usage, Calendar Sets와 provider account/list UI는 긴 account/calendar/provider/Set 이름, keyboard, scroll과 VoiceOver에서 의미를 잃지 않아야 한다. membership은 Included/Not included, disabled와 unavailable 상태를 색만으로 전달하면 안 되며 자동·offscreen 결과만으로 실제 접근성 통과를 선언하면 안 된다. |

### 4.11 상용 기능 후속 요구사항

상세 우선순위, 시장 비교, 실패 경계와 단계 정의는
[상용 기능 격차와 후속 구현 로드맵](commercial-feature-roadmap.md)을 정본으로 한다.
`C0~C4`는 Phase 0~10이나 provider `T0~T5`와 다른 후속 상용화 순서다.

| ID | 단계 | 상태 | 최소 인수 기준 |
| --- | --- | --- | --- |
| `COM-001` | C1 | 설계 승인 / 구현 대기 | 일정·local task notification을 명시적으로 설정·해제하고 due와 reminder 의미를 분리하며, 권한 거부·변경·완료·삭제·재실행 뒤 중복 예약을 만들지 않아야 한다. |
| `COM-002` | C1 | 설계 승인 / 구현 대기 | 제목·장소·calendar/source·날짜 범위로 bounded EventKit 검색을 제공하고 검색 범위를 공개하며 exact occurrence와 temporary reveal로 이동해야 한다. |
| `COM-003` | C1 | 구현·자동/offscreen 검증 완료 / live 대기 | 일정 제목과 시간 정보를 보여 주는 본문 Month view가 locale·주 시작·4~6주의 완전한 주, all-day/timed multi-day의 주별 segment, 배타 종료, `+N` overflow와 날짜별 popover, `global Enabled ∩ 선택 Calendar Set`을 보존해야 한다. event 선택은 기존 Inspector로 이어지고 날짜 동작은 해당 Day로 이동해야 하며, 상단 Day/Week/Month/Agenda 전환기와 `⌘1`~`⌘5`, 방향키 focus와 VoiceOver 의미를 제공해야 한다. 첫 버전에는 일정 drag 이동·resize, Quarter/Year, 전체 검색, Day Summary와 Quick Add/template을 포함하지 않는다. |
| `COM-004` | C1 | 설계 승인 / 구현 대기 | keyboard Quick Add와 이 Mac에 저장하는 deterministic template을 제공하되 AI·자연어 추론·원격 생성 기능을 추가하면 안 된다. |
| `COM-005` | C1 | 설계 승인 / 구현 대기 | EventKit snapshot에서 안전한 HTTPS 회의 링크 후보를 감지해 사용자가 선택·열 수 있게 하되 notes/URL 원문을 새 local 정본으로 복제하면 안 된다. |
| `COM-006` | C2 | 구현 / live 대기 | 명시적 drag는 현재 Calendar Set의 writable calendar에 15분 단위·기본 1시간 block과 During task를 만들고 exact provider task를 연결해야 한다. 자동 재배치·완료 전파는 하지 않으며 부분 성공을 조용한 task 삭제로 보정하면 안 된다. |
| `COM-007` | C2 | 로드맵 승인 / 설계 대기 | Command Bar와 menu bar는 Today, 검색, Quick Add, Set 전환과 다음 일정을 keyboard-first로 제공하되 별도 데이터 정본을 만들지 않아야 한다. |
| `COM-008` | C2 | 로드맵 승인 / 설계 대기 | primary/secondary time zone을 동시에 표시하면서 all-day/floating/zoned 원본 의미나 저장값을 바꾸면 안 된다. |
| `COM-009` | C2 | 로드맵 승인 / ADR 대기 | 사용자 명시 시간 규칙의 Mac-local Set 자동 전환은 편집·notes flush·recovery·temporary reveal을 방해하지 않아야 하며 위치 규칙은 별도 권한/Privacy ADR 전에는 구현하지 않는다. |
| `COM-010` | C2 | 로드맵 승인 / 설계 대기 | EventKit이 제공하는 URL·attachment metadata·organizer·응답 상태를 안전하게 표시하고 지원하지 않는 write는 Calendar.app exact-event 왕복으로 설명해야 한다. |
| `COM-011` | C2 | 구현 / live 대기 | local task의 예상/실제 duration·반복·priority·중요 표시·checklist는 local planning overlay로 보존하고 provider 의미 손실 가능성이 있으면 write하지 않거나 명시적 capability 제한을 보여 줘야 한다. |
| `COM-012` | C3 | 로드맵 승인 / 설계 대기 | 저장된 reference metadata의 local search·정렬·grouping만 검토하며 remote preview, background crawler, 본문 저장과 양방향 notes sync를 포함하지 않는다. |
| `COM-013` | C3 | 로드맵 승인 / ADR 대기 | 선택한 과거 KaosCal archive importer는 격리 staging DB에서만 migration하고 preflight 실패 시 active DB와 원본 archive를 보존해야 한다. |
| `COM-014` | C3 | 재평가 대기 | Quarter/Year와 현재 EventKit snapshot 기반 local summary는 C1 Month·검색 결과 뒤 평가하되 telemetry, remote analytics, weather API와 AI summary를 도입하지 않는다. |

## 5. 핵심 상태 전이

### 5.1 Calendar 권한

```text
notDetermined ── request/allow ──> fullAccess ── revoke ──> denied/restricted
      │                                │
      └─ request/deny ────────────────>┘

writeOnly / unknown ──> 설명 가능한 제한 상태, event fetch 없음
fullAccess 복구 ──────> calendar와 현재 범위 재조회
```

### 5.2 Event link 복구

```text
active
  ├─ strong found/cancelled ───────────────> active + snapshot/lifecycle 갱신
  ├─ explicit lookup notFound ─────────────> missing
  └─ error/candidate/ambiguous/inconclusive -> 상태 유지

missing
  ├─ strong found ─────────────────────────> active
  ├─ explicit Recheck + notFound ──────────> orphan review
  └─ verified Relink ──────────────────────> active + relink log

orphan review
  ├─ Keep as orphan ───────────────────────> orphaned
  ├─ verified Relink ──────────────────────> active
  └─ Delete local Brief ───────────────────> SQLite context cascade delete only
```

### 5.3 외부 task binding

```text
local-only
  ├─ usable destination ─> pending-create ─> linked
  └─ unavailable ────────> local-only

linked
  ├─ expected-version write success ───────> linked
  ├─ version mismatch ─────────────────────> conflict
  ├─ remote deletion ──────────────────────> missing
  ├─ disconnect ───────────────────────────> disconnected/local-only 보존
  └─ auth/network error ───────────────────> 설명 가능한 pending/error
```

## 6. 데이터 스키마 기준선

| Migration | 책임 |
| --- | --- |
| `v1_context_store` | event context/link/task, personal task |
| `v2_event_change_log` | 원본 변경 history와 Undo audit |
| `v3_calendar_clarity` | explicit calendar role preference |
| `v4_task_provider` | provider account/item/binding/destination/cursor 기반 |
| `v5_oauth_task_providers` | OAuth provider identity, pending mutation과 민감 cache 정리 |
| `v6_context_references` | URL reference-only persistence |
| `v7_microsoft_to_do_provider` | Microsoft To Do provider 확장 |
| `v8_calendar_usage` | visibility/blocking sparse preference |
| `v9_saved_calendar_sets` | named Set, exact calendar membership과 persisted role/saved selection |
| `v10_task_provider_recovery` | task별 create/update/delete pending, bounded retry와 durable local-only preference |
| `v11_local_task_planning` | local Event/Personal task priority, repeat, estimate/actual timer와 checklist overlay |

스키마의 column, CHECK, foreign key, index와 backup manifest의 정확한 계약은
[Data Model](data-model.md)과 migration source를 따른다. 이 표는 migration을 재정의하지 않는다.

## 7. 비기능 요구사항

| ID | 요구사항과 인수 기준 |
| --- | --- |
| `SAFE-001` | 사용자 Confirm 전, 또는 identity·권한·scope가 불명확할 때 원본 Calendar write를 0회로 유지해야 한다. |
| `SAFE-002` | EventKit write와 SQLite transaction이 원자적이지 않음을 숨기지 않고 부분 성공을 명시해야 한다. 자동 재시도로 원본을 두 번 바꾸면 안 된다. |
| `SAFE-003` | Calendar 원본 삭제와 local Brief 삭제, provider task 삭제와 local task 삭제를 각각 별도 명령으로 유지해야 한다. |
| `PRIV-001` | 실제 계정 이메일, raw remote/event ID, credential, token, 사용자 본문을 log·문서·test fixture에 기록하면 안 된다. |
| `PRIV-002` | backup의 plaintext·current-schema-only·무서명 성격과 사용자 책임을 UI/문서에서 숨기면 안 된다. |
| `PERF-001` | duplicate 후보는 fetch snapshot당 한 번 계산해 event ID index로 조회하고, card render마다 전체 event pair를 다시 비교하면 안 된다. |
| `PERF-002` | EventKit 변경 알림과 range fetch는 중복 요청을 병합·취소할 수 있어야 하며 UI navigation이 stale 원본 객체에 의존하면 안 된다. |
| `ACC-001` | icon-only 상태는 접근성 label/help를 가져야 하고 source, role, restriction, sync 상태는 색만으로 구분하면 안 된다. |
| `REL-001` | 자동 test, offscreen render, live provider/Exchange, exact Release audit를 서로 다른 증거 등급으로 기록해야 한다. 낮은 등급의 증거로 높은 등급 gate를 통과시켜서는 안 된다. |
| `REL-002` | update build number는 단조 증가해야 하고 Sparkle private key를 source·`.env`·app bundle·log에 넣어서는 안 된다. appcast/archive 서명 뒤 byte를 바꾸지 않으며, 직전 notarized build에서 발견·설치·재실행·local DB 보존을 통과하기 전 자동업데이트 배포를 선언하면 안 된다. |

## 8. 명시적 제외 범위

- AI/LLM/ML 기반 생성·요약·분류·추천·검색·자동 스케줄링·자동 재배치·수락·삭제
- KaosCal 계정·backend·cloud database·sync relay·remote config·telemetry와
  Event Brief/Task/Calendar Set cloud/device sync
- 모바일·웹 companion, 팀 협업, 공유 프로젝트와 Kanban
- RSVP, 참석자·주최자 관리와 attendee meeting 원본 편집
- Google/Microsoft/CalDAV/iCloud Calendar 직접 sync engine
- 안전하게 표현할 수 없는 복잡 recurrence 강제 편집
- linked future series의 전체 context reconciliation 없는 write
- 일반적인 multi-step/app-restart Undo
- calendar color/name override와 Calendar Set cloud/device sync. Mac-local 시간 자동 전환은
  `COM-009`, 위치 자동 전환은 별도 권한·privacy ADR 전까지 구현 대기다.
- duplicate 자동 merge/hide/delete
- 외부 notes 본문 양방향 sync와 reference의 task 자동 변환
- backup record merge, scheduled backup, automatic retention/pruning
- 미래 schema downgrade, 임의 SQLite 복구, record merge와 backup 없는 destructive bootstrap
  reset. 선택한 과거 KaosCal archive migration은 `COM-013`의 별도 staging importer로만 검토한다.
- Developer ID/notarization/stapling을 통과하지 않은 build의 외부 배포 완료 선언

## 9. 인수와 증거 규칙

### 9.1 공통 Definition of Done

기능 변경은 다음을 모두 충족해야 한다.

1. 이 문서에 새 요구사항 ID를 추가하거나 기존 ID의 동작·인수 기준을 먼저 변경한다.
2. 제품·안전·데이터 결정이 바뀌면 새 ADR 또는 기존 ADR 상태를 갱신한다.
3. 정상 흐름, 취소/no-op, 권한·identity·provider 실패, 데이터 보존을 자동 테스트한다.
4. 사용자 동작은 QA checklist에 재현 절차와 기대 결과를 추가한다.
5. 전체 non-manual test에서 예상하지 않은 failure와 skip이 0이어야 한다.
6. 실제 provider/EventKit을 주장하는 기능은 비민감 fixture, exact artifact/run, cleanup과
   residue를 기록한다.
7. current status와 implementation log에 최신 판정과 증거를 함께 갱신한다.

### 9.2 증거 등급

| 등급 | 증명할 수 있는 것 | 증명할 수 없는 것 |
| --- | --- | --- |
| 자동 unit/integration | domain, DB, fake provider, deterministic UI state | 실제 Exchange/provider/API 동작 |
| offscreen/fixture render | 고정 크기 layout과 기본 문구 | 실제 window focus, scroll, keyboard, VoiceOver |
| signed live run | exact build의 macOS 권한·EventKit/provider·실창 동작 | 다른 build와 clean-user 배포 |
| Release audit | 서명·entitlement·runtime·artifact 무결성 | notarization과 외부 사용자 환경 |
| notarized clean-user run | 설치·실행·회수 경로 | 모든 provider/account 조합 |

## 10. 요구사항 추적성

| 요구사항 | 설계·결정 | 주요 구현 | 자동 검증 |
| --- | --- | --- | --- |
| `SYS-001`–`SYS-003`, `CAL-001`–`CAL-006` | [Architecture](architecture.md), [EventKit Decisions](eventkit-decisions.md), [ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md) | `KaosCalApp`, `AppState`, `CalendarProvider`, `EventKitProvider`, task provider client/Keychain 경계 | `CalendarAccessTests`, `AppStateTests`, provider/local-only contract tests |
| `SYS-004`, `REL-002` | [ADR-020](adr/ADR-020-signed-automatic-updates.md), [Release Runbook](release-runbook.md) | `UpdateController`, Info.plist updater policy, sandbox entitlements, Sparkle 2 | `UpdateConfigurationTests`, app payload/signature audit, previous-build upgrade smoke |
| `UI-001`–`UI-004`, `TIME-*` | [ADR-003](adr/ADR-003-all-day-time-zone-and-recurrence.md), [ADR-007](adr/ADR-007-calendar-layout-and-display-time.md) | `CalendarTimelineView`, `CalendarEventLayout`, `CalendarEventDateFormatting` | `CalendarEventLayoutTests`, `CalendarEventEditingTests` |
| `CAL-007`, `UI-005` | [ADR-002](adr/ADR-002-calendar-and-task-experience.md) | `MiniMonthGrid`, `MiniMonthView`, `AppState`, `CalendarEventDateFormatting` | `AppStateTests`, `CalendarEventLayoutTests`, mini month live QA |
| `COM-003` | [상용 기능 로드맵](commercial-feature-roadmap.md), [Design System](design-system.md), [Architecture](architecture.md) | `MonthGrid`, `MonthEventLayout`, `MonthCalendarView`, `AppState`, calendar view picker와 navigation commands | `AppStateTests`, `CalendarEventLayoutTests`, Full Month live QA |
| `CFG-001`–`CFG-005` | [ADR-014](adr/ADR-014-multi-calendar-clarity.md) | `CalendarClarity`, `CalendarRoleRepository`, `AppState` | `CalendarClarityTests`, `AppStateTests` |
| `CFG-006`–`CFG-011` | [ADR-017](adr/ADR-017-calendar-visibility-and-availability.md) | `CalendarClarity`, `CalendarRoleRepository`, Settings/Sidebar, `AppState` | `CalendarClarityTests`, `AppStateTests`, backup tests |
| `EVT-*` | [ADR-010](adr/ADR-010-original-event-write-safety.md), [ADR-011](adr/ADR-011-recurrence-move-change-log-and-session-undo.md) | `CalendarEventEditing`, `EventKitProvider`, `EventEditorView`, `AppState` | `CalendarEventEditingTests`, `AppStateTests` |
| `CTX-*`, `TASK-001`–`TASK-004` | [ADR-008](adr/ADR-008-local-context-store-and-event-identity.md), [ADR-009](adr/ADR-009-event-brief-and-task-center-interactions.md) | `ContextStore`, context/task repositories, Event Brief, Task Center | `ContextStoreTests`, `LocalWorkspaceTests` |
| `TASK-005`–`TASK-011`, `COM-006`, `COM-011` | [Design System](design-system.md), [Architecture](architecture.md), [상용 기능 로드맵](commercial-feature-roadmap.md) | `TaskProviderCoordinator`, `ProviderTaskSidebarView`, `ProviderTaskEditorSheet`, `TaskCenterView`, `TaskPlanningRepository`, calendar drop/link route | `ContextStoreTests`, `AppStateTests`, 300/360pt offscreen render, provider/calendar signed fixtures |
| `LCY-*` | [ADR-012](adr/ADR-012-lifecycle-after-review-and-orphan-confirmation.md) | `ContextStore`, `EventContextRepository`, `AppState` | `ContextStoreTests`, `LocalWorkspaceTests`, editing tests |
| `PRV-*` | [v2 실행계획](v2-execution-plan.md), [T0–T4](v2/README.md), [ADR-016](adr/ADR-016-direct-calendar-api-deferral.md) | task provider models/repository/adapters/OAuth session, Settings | `ContextStoreTests`, `AppStateTests` |
| `REF-*` | [T5](v2/phase-t5-notes-reference.md) | `ContextReferenceRepository`, Event Brief | `ContextStoreTests` |
| `DATA-*`, `BAK-*` | [Data Model](data-model.md), [ADR-015](adr/ADR-015-backup-import-reset-safety.md), [Backup and Restore](backup-restore.md) | migrations, `ContextStore`, `LocalDataBackupService`, Settings | `ContextStoreTests`, `LocalDataBackupServiceTests`, `AppStateTests` |
| 나머지 `COM-*` | [상용 기능 로드맵](commercial-feature-roadmap.md), [ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md), 구현 전 필요한 후속 ADR | 상태별 구현 대기 | 요구사항별 자동·offscreen·live gate를 구현 변경과 함께 추가 |

## 11. 스펙주도 변경 절차

새 기능이나 동작 변경은 아래 순서를 기본으로 한다.

1. **Specify:** 기존 ID를 바꾸거나 새 ID를 추가하고 사용자 시나리오·실패 경계·인수 기준을 적는다.
2. **Decide:** 대안과 되돌리기 어려운 제품/데이터 결정은 ADR로 고정한다.
3. **Test:** 인수 기준을 자동 계약과 필요한 live QA fixture로 변환한다.
4. **Implement:** source of truth와 write boundary를 지키는 최소 변경을 구현한다.
5. **Verify:** 전체 자동 회귀와 요구되는 수동/live/Release gate를 실행한다.
6. **Record:** current status, implementation log, known issues와 사용자 문서를 같은 변경에서 갱신한다.

새 요구사항은 다음 최소 형식을 사용한다.

```md
### <ID> — <제목>

- 상태/대상 버전:
- 사용자 시나리오:
- 해야 하는 동작:
- 하지 않아야 하는 동작:
- 데이터·권한 영향:
- 실패/복구 경계:
- 자동 인수 기준:
- live/manual 인수 기준:
- 관련 ADR·코드·테스트:
```

요구사항 ID는 구현 후 의미를 다른 기능으로 재사용하지 않는다. 폐기된 요구사항은 삭제해
번호를 당기지 않고 `Superseded` 또는 `제외`와 대체 ID/ADR을 남긴다.

## 12. 현재 열려 있는 검증·결정

현행 구현의 상세 최신 상태는 [Current Status](current-status.md)를 따르며, 특히 다음은
자동 구현과 분리된 gate다.

- mini month `CAL-007`/`UI-005` dot의 실제 창·VoiceOver와 provider 지연/오류 live 검증
- 실제 Exchange all-day, floating/zoned, recurring `thisEvent`/future split과 calendar move
- shared read-only Exchange와 identifier churn/detached occurrence recovery
- Calendar visibility/blocking의 실제 Settings·Sidebar·고밀도·VoiceOver 검증
- Apple Reminders, Google Tasks, Todoist, Microsoft To Do의 실제 계정 fixture와 cleanup
- 실제 export/import/reset mutation과 손상 sandbox DB recovery
- final exact Release의 onboarding, keyboard/VoiceOver와 clean-user 실행
- Developer ID signing, notarization, stapling, 승인 EULA와 support/privacy 연락처
- signed HTTPS appcast 발행과 직전 notarized build의 end-to-end 자동업데이트
- C1 `COM-003` Full Month의 실제 창 keyboard·VoiceOver·고밀도 live 검증
- C1 `COM-001`, `COM-002`, `COM-004`, `COM-005`의 상세 설계와 구현. C2/C3는
  [상용 기능 로드맵](commercial-feature-roadmap.md)의 ADR 순서를 따른다.

tentative event를 soft conflict로 분리할지, account-level calendar usage 기본값을 상속할지,
identifier churn 뒤 preference를 수동 복구하는 UX는 후속 ADR이 필요한 열린 제품 결정이다.
