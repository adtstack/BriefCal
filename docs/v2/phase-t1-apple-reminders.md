# T1 — Apple Reminders

> 상태: implemented / live pending
> 선행: [T0 Provider abstraction](phase-t0-provider-abstraction.md)

## 목표

macOS native Reminders를 첫 외부 task provider로 연결한다. Calendar 권한과 Reminders
권한은 별개로 취급하며, 계정 이름만으로 지원 여부를 추측하지 않는다.

## 구현 checkpoint (2026-07-13)

- `AppleRemindersProvider`가 full-access 권한, writable list 조회, 생성·제목/due/완료 수정,
  optimistic version 확인 삭제, 외부 변경 callback을 제공한다.
- Settings에 Reminders 권한 요청과 calendar별 destination list 선택을 추가했다.
- Event Brief event task의 생성·수정·완료·삭제를 선택 destination에 연결하고, 외부 변경은
  linked local projection을 갱신한다. 외부 삭제는 local task를 지우지 않고 `missing`으로 남긴다.
- Reminders entitlement와 `NSRemindersFullAccessUsageDescription`을 target에 반영했다.
- 실제 iCloud/On My Mac list fixture, permission revoke, cleanup은 아직 실행하지 않았다.

## Tasks 직접 관리 checkpoint (2026-07-20)

- 오른쪽 `Tasks`의 완료 원을 실제 Apple Reminders 완료/미완료 명령으로 연결했다.
- `+`와 상세 sheet에서 writable list 선택, 제목·전체 notes·기한 설정/제거·완료·삭제를
  지원한다. 상세 진입은 최신 remote snapshot을 다시 읽는다.
- SwiftUI row ID와 remote task ID를 분리하고 provider/account/list/task/version을 모두
  확인한다. read-only 또는 list metadata 실패 상태에서는 조회만 허용한다.
- version mismatch는 자동 재시도나 덮어쓰기 없이 draft를 보존한 conflict로 중단한다.
- 성공 후 provider 목록과 linked Event Task projection을 다시 읽는다. remote 삭제는 local
  Event Task를 지우지 않고 missing/Needs attention으로 남긴다.
- 일반 Reminders task의 notes는 SQLite·backup에 저장하지 않는다. 이 checkpoint 뒤 공통
  mutation route, Event Brief 연결과 calendar time block이 별도 Tasks 완성 트랙에서 구현됐다.
- 상세 sheet에서 writable Apple list를 바꿔 목록·계정 사이로 이동할 수 있다. 이미 Event
  Brief에 연결된 reminder는 remote move와 durable binding parent/account를 함께 갱신한다.
- 선택 모드는 여러 Apple reminder의 완료·미완료와 list 이동을 제공한다. 생성·수정·이동·
  삭제·일괄 변경 뒤에는 fresh version이 그대로일 때만 실행되는 process-local Undo를 표시한다.
  삭제 Undo로 ID가 바뀌면 local Event Task를 새 remote ID에 재연결한다.
- EventKit reminder의 `url`은 사용자가 넣은 내용일 수 있어 Reminders.app deep link로 노출하지
  않는다. Microsoft Graph가 task 원본 URL을 반환한 경우만 조회 행에서 연다.

따라서 T1 판정은 `implemented / live pending`이다. 아래 범위는 T1 당시 계약이며, 이후
T2/T3와 Tasks 완성 트랙은 공통 스펙과 Current Status에서 별도로 추적한다.

## 제공 범위

- Reminders 접근 권한 요청·거부·철회 상태
- 사용자가 선택한 Reminders list를 destination으로 저장
- 지정된 calendar의 새 Event Brief task 생성
- 제목, due, 완료, 삭제의 양방향 반영
- Reminders에서 외부 완료한 task의 BriefCal projection 갱신
- remote deletion의 missing 표시와 명시적 relink/unlink
- `Reminders · <list>` destination badge와 local-only fallback

반복 checklist, list 간 자동 복제, 전체 Reminders 검색, 원본 event notes 쓰기는 범위에서
제외한다. SDK의 실제 capability 이름과 권한 usage description은 T1 착수 시 target
macOS SDK에서 확인하고 문서·entitlement를 함께 갱신한다.

## 사용자 흐름

1. Settings에서 Calendar 또는 Calendar account를 선택한다.
2. 외부 task destination을 Reminders로 켠다.
3. 권한이 없으면 권한 요청과 System Settings 복구 경로를 먼저 표시한다.
4. 사용자가 list를 선택하고 capability 결과를 확인한다.
5. Event Brief에서 새 task를 만들면 provider 선택 UI 없이 해당 list에 생성한다.
6. 생성 성공 전에는 local task에 pending badge를 표시하고, 실패 시 local-only fallback
   또는 Retry/Keep local 선택지를 보여 준다.
7. Reminders에서 완료·제목·due를 바꾸면 refresh 뒤 Task Center를 갱신한다.
8. 외부 삭제는 local task를 지우지 않고 missing 상태로 남긴다.

## 매핑 계약

| BriefCal | Reminders | 규칙 |
| --- | --- | --- |
| title | title | 공백 정리 후 저장, 원본 notes와 분리 |
| section | tag/metadata 또는 local link | provider가 section을 보존하지 않으면 BriefCal만 정본 |
| fixed due | due | 시간·시간대 capability 확인 후 변환 |
| relative due | 계산된 due | 변환 결과가 의미를 잃으면 자동 연결 금지 |
| completed | isCompleted | provider write 성공 뒤 local projection 갱신 |
| context link | URL/deep link 검토 | 보존되지 않으면 account/list/remote ID로 재연결 |

## 구현 순서

1. Reminders provider adapter와 capability probe
2. 권한·list 선택 Settings와 destination persistence
3. create/update/complete/delete의 provider call과 receipt 처리
4. provider observation 또는 refresh 기반 remote-to-local sync
5. missing/relink/disconnect와 fallback UI
6. 실제 fixture를 사용한 signed Release 수동 QA

## 테스트·live fixture

- fake Reminders provider에서 모든 mutation이 예상 scope로만 호출되는지 검증
- permission denied, revoked, read-only list, unavailable list를 분리
- 같은 제목의 task가 두 list에서 충돌하지 않는지 검증
- Calendar event의 notes/attendee/시간이 한 번도 쓰이지 않는지 검증
- create 중 앱 종료, 완료 toggle 중 네트워크 실패, remote deletion 후 재연결 검증
- iCloud list와 On My Mac list를 각각 최소 한 번 확인
- 실제 list에서 Before/During/After 각 1개를 생성하고 완료·삭제·cleanup
- Settings destination을 local-only로 바꾼 뒤 기존 Reminders task가 임의 삭제되지 않는지 확인

## 종료 게이트

Reminders 권한·list 선택·생성·완료·수정·삭제·missing/relink가 실제 fixture에서
통과하고, cleanup 뒤 orphan task가 남지 않아야 한다. 자동 테스트만 통과한 경우는
`implemented / live pending`으로 기록한다.
