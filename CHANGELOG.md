# Changelog

KaosCal의 사용자에게 보이는 변경과 release 경계를 기록한다. 날짜가 없는 항목은 아직
배포되지 않은 상태이며, 실제 release artifact와 검증 결과는
[Release Runbook](docs/release-runbook.md)에 따라 별도로 기록한다.

## [0.1.0] - Unreleased

### Added

- **Phase 0 — Repo bootstrap:** macOS SwiftUI app shell, shared Xcode scheme, 문서·ADR·QA
  기준선과 ad-hoc build 검증을 추가했다.
- **Phase 1 — EventKit read-only:** macOS Full Calendar Access 상태, Calendar에 구성된
  Exchange source/calendar 조회, read-only/writable 표시와 변경 알림 refresh를 추가했다.
- **Phase 2 — Calendar layout:** Day, Week, Agenda의 공통 event 표현, timed overlap,
  all-day/multi-day lane, DST/time-zone aware layout과 sidebar mini month를 추가했다.
- **Phase 3 — Local context DB:** GRDB 기반 SQLite migration, Event Brief/task repository,
  strong event identity와 local-first persistence를 추가했다.
- **Phase 4 — Event Brief and Task Center:** Before/During/After task, notes autosave,
  personal task, Today/Upcoming/Completed projection과 inline editing을 추가했다.
- **Phase 5 — Original event editing:** attendee가 없는 writable 단일 일정의 안전한
  create/update/delete, all-day/time-zone preview와 최신 원본 preflight를 추가했다.
- **Phase 6 — Recurrence and safe move:** 명시적 `이번 일정`/`이번 이후` 영향 확인,
  linked calendar move reconciliation, additive change log와 제한된 in-session Undo를
  추가했다.
- **Phase 7 — Lifecycle and recovery:** scheduled/completed/cancelled/orphaned lifecycle,
  After Review, 두 번의 명시적 missing 확인, local Brief 보관·재연결·삭제, linked original
  delete review/finalize를 추가했다.
- **Phase 8 — Multi-calendar clarity:** local calendar role, role별 virtual Set, source와
  typed permission/restriction 표시, 비파괴 possible-duplicate review를 추가했다.
- **Saved Calendar Sets:** synthetic All과 Smart Role Filter에 더해 사용자 이름의 저장 Set,
  CRUD·순서·exact calendar membership·현재 선택 persistence, missing membership 보존과
  명시적 Replace, global Enabled master mask와 duplicate/relink temporary reveal을 추가했다.
- **Phase 9 — Backup and Settings:** healthy current-schema DB의 strict two-entry plaintext
  ZIP export/import, import/reset 전 recovery backup, 현재 local-data table reset,
  rollback-failure quarantine과 Local Data Settings를 추가했다.
- **Phase 10 paid-beta polish:** first-run privacy/workflow onboarding, `⌘R` reload,
  Day/Week empty-state 안내와 DB open/migration 실패 시 strict same-schema backup을 고르는
  bootstrap recovery를 추가했다. recovery는 검증 전 active 파일을 건드리지 않고 기존
  SQLite/sidecar를 private `Recovery` 폴더에 격리하며 설치 실패 시 rollback한다. current
  status, 사용자 가이드, known issues, privacy/security 경계, release runbook, contributor
  guide, changelog, beta-license placeholder와 third-party notice도 추가했다. 이는 실제
  Developer ID 배포·지원 채널·승인된 앱 license/EULA 완료를 의미하지 않는다.

### Security and safety

- EventKit 원본 일정과 KaosCal local Event Brief/task를 분리하고 invitation/attendee,
  read-only, weak identity와 지원하지 않는 recurrence write를 보수적으로 차단한다.
- Backup import는 application identifier, migration ledger, schema, byte/hash, SQLite
  integrity와 foreign key를 검사하며 EventKit write를 수행하지 않는다.
- Release configuration은 hardened runtime, sandbox, Calendar와 user-selected file
  entitlement를 사용하고 `get-task-allow`와 XCTest payload를 제외한다.

### Known limitations

- 사용자 관점의 전체 목록과 안전한 우회 방법은
  [Known Issues and Current Limits](docs/known-issues.md)를 따른다.
- 0.1.0은 아직 `Unreleased`다. Developer ID signing, notarization/stapling, 최종 package,
  clean-user smoke와 외부 beta 운영은 [Release Runbook](docs/release-runbook.md)의 pending
  gate다.
- Calendar.app 시각 round-trip, live all-day/floating/zoned 편집, 반복 `thisEvent`/
  future split, linked calendar move, 외부 삭제 지연과 shared read-only Exchange는 각각
  독립 live gate가 남아 있다. 현재 판정은 [Current Status](docs/current-status.md), 사용자
  영향과 우회는 [Known Issues](docs/known-issues.md)를 따른다.
- 참석자가 있는 meeting과 invitation의 RSVP·참석자·원본 제목/시간/삭제 변경, 복잡한
  recurrence와 detached occurrence의 future write는 KaosCal v1에서 제공하지 않는다.
  전체 지원/제외 범위는 [V1 Scope](docs/v1-scope.md)에 있다.
- KaosCal은 Microsoft Graph/EWS나 자체 sync engine을 사용하지 않고 macOS Calendar에
  구성된 EventKit source만 사용한다. 온프레미스 Exchange 지원은 약속하지 않는다.
- Backup은 암호화·서명되지 않은 plaintext이고 record merge, scheduled backup,
  automatic retention/pruning이 없다. 실행 중 build와 exact current schema/migration이
  같은 신뢰 가능한 backup만 import한다.
- 손상 live DB 때문에 app bootstrap이 실패하면 현재 schema와 정확히 맞는 KaosCal
  backup만 선택할 수 있다. 임의 SQLite, schema migration/downgrade, record merge와
  backup 없는 destructive reset은 지원하지 않는다. 실제 signed Release 손상 DB 복구는
  아직 manual pending이며 자세한 경계는 [Backup and Restore](docs/backup-restore.md)에 있다.
- Undo는 같은 session의 좁은 supported mutation에만 적용되며 app 재실행, recurrence,
  detached occurrence와 delete의 일반 복구 수단이 아니다.
- saved Calendar Set의 cloud/device sync, 시간·위치 기반 자동 전환, calendar별 color/name
  override, automatic duplicate merge와 모바일/team collaboration은 현재 범위 밖이다.
