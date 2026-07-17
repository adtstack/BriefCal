# Backup, Restore, and Local Reset

## 범위

Phase 9의 Local Data 설정은 KaosCal이 소유한 로컬 SQLite 데이터만 다룬다.
Export, import, reset 어느 경로도 EventKit을 호출해 Calendar.app 또는 Exchange의
일정을 만들거나 수정하거나 삭제하지 않는다.

수동 export는 현재 schema까지 정상적으로 열리고 migration이 끝난 파일 기반
production DB에서만 제공한다. in-memory test store, DB open/migration 실패 상태,
저장에 실패한 Event Brief notes가 남은 상태에서는 시작하지 않는다.

## 백업 파일 계약

수동 export와 import/reset 전 자동 백업은 SQLite의 online backup API로 현재
`DatabaseWriter`와 직렬화된 snapshot을 만든다. WAL 파일을 따로 복사하거나 실행
중인 DB 파일을 filesystem copy하지 않는다.

ZIP은 store-only 방식이며 root에 정확히 두 entry만 포함한다.

```text
KaosCal-Backup-YYYY-MM-DD-HHmm.zip
├─ kaoscal.sqlite
└─ manifest.json
```

하위 폴더, symlink, 중복 이름, `-wal`/`-shm`, Finder metadata와 다른 payload는
허용하지 않는다. archive format version은 SQLite schema version과 별도다.
현재 DB schema의 마지막 migration은 `v10_task_provider_recovery`이며 import는
manifest에 기록된 migration 목록과 실제 SQLite migration table을 함께 확인한다.

format v1 제한은 다음과 같다.

- `manifest.json` 최대 64 KiB
- `kaoscal.sqlite` 최대 128 MiB
- 전체 ZIP 최대 129 MiB
- classic single-disk, UTF-8, store-only entry만 허용
- deflate, encryption, data descriptor, ZIP64, multi-disk, extra/comment/attribute,
  trailing bytes와 entry 사이 gap/overlap은 거부

따라서 export한 ZIP을 풀었다가 일반 압축 도구로 다시 압축한 파일은 호환 backup으로
간주하지 않는다.

manifest format v1은 key 추가/누락도 거부하며 다음 값을 정확히 기록한다.

- `backup_format_version`
- `application_identifier`, `application_version`, `exported_at`
- `schema_version`, 마지막 migration인 `schema_identifier`, 전체
  `applied_migrations`
- `database_filename`, `database_byte_count`, `database_sha256`
- `contains_complete_calendar_events = false`
- `contains_linked_event_snapshots = true`, `contains_event_briefs = true`
- `is_encrypted = false`

기기 이름은 기록하지 않는다. `source_machine_name` 같은 host 식별 metadata는 현재
format에 없다.

## 포함 데이터와 개인정보

`kaoscal.sqlite` snapshot에는 다음 로컬 데이터가 포함될 수 있다.

- Event Brief notes와 Before/During/After task
- personal task
- event link의 title, time, location, calendar/source identifier 같은 연결 metadata
- change log와 그 versioned before/after snapshot
- change snapshot에 보존된 원본 event notes snapshot
- local calendar role preference
- local calendar visibility와 availability-blocking preference
- saved Calendar Set 이름·순서, exact calendar membership과 현재 선택

KaosCal은 계정 credential, Exchange password, MFA code, OAuth token이나 attendee
전체 목록을 전용 필드로 수집·저장하지 않고 EventKit의 전체 event store도 export하지
않는다. 그러나 Event Brief notes와 task 본문은 검사하거나 redact하지 않는다. 사용자가
그 본문에 입력한 credential이나 다른 민감정보는 그대로 backup에 포함될 수 있으며,
위의 연결 metadata와 원본 notes snapshot도 민감할 수 있다.

KaosCal은 ZIP이나 SQLite를 암호화하거나 서명하지 않는다. 사용자가 선택한
로컬·외장·cloud 폴더에는 plaintext로 저장되므로 신뢰하는 위치에 보관해야 한다.

## 수동 Export

App Sandbox 밖의 파일은 `NSSavePanel`에서 사용자가 명시적으로 고른
security-scoped URL만 쓴다. user-selected read/write entitlement는 이 선택 파일에만
사용하고 자동 recovery backup은 app container의 Application Support에 둔다.

1. Settings의 `Local Data`에서 `Export Backup…`을 선택한다.
2. 저장 위치와 `.zip` 파일명을 고른다.
3. KaosCal은 같은 writer에서 consistent SQLite snapshot을 만들고 manifest를
   생성한 뒤 strict two-entry ZIP으로 완성한다.
4. 완료 전 실패하면 이 시도가 만든 partial destination archive를 commit하지 않는다.
   같은 이름의 기존 파일이 있었다면 final atomic replace 전에는 그대로 유지된다.

수동 export는 사용자가 요청할 때만 실행한다. Phase 9에는 schedule 기반 자동
backup이나 보관 개수/기간 정책이 없고 기존 backup을 자동 삭제하지 않는다.

## Import

Import는 merge가 아니라 active KaosCal local DB 전체 교체다. 사용자가 ZIP을
선택하고 destructive confirmation을 승인한 뒤 다음 순서로 진행한다.
Sandbox 밖의 source는 `NSOpenPanel`에서 사용자가 고른 security-scoped URL만 읽는다.

1. archive type, root entry 이름·개수와 store-only encoding을 검사한다.
2. manifest format, migration/schema 호환성, byte count와 SHA-256을 검사한다.
3. 추출한 SQLite에서 `integrity_check`, foreign-key violation, migration 목록을
   검사한다.
4. 현재 active DB를 Application Support의 `Backups` 폴더에 자동 ZIP으로 먼저
   저장한다.
5. 검증된 SQLite snapshot을 같은 live `DatabaseWriter`에 online restore한다.
6. restore 뒤 schema, integrity와 foreign key를 다시 확인하고 local projection을
   다시 읽는다.

SHA-256은 manifest와 SQLite entry의 byte 일치를 확인하는 값이며 backup 제작자를
인증하는 서명은 아니다. 사용자가 직접 만든 신뢰 가능한 KaosCal backup만 선택한다.
Phase 9은 실행 중인 앱의 application identifier, current schema object와 migration
목록이 정확히 같은 backup만 허용한다. app version이 달라도 이 계약이 같으면
import할 수 있지만 과거 schema를 자동 migration하거나 미래 schema를 downgrade하지
않는다.

검증 실패는 active DB를 건드리지 않는다. restore 또는 사후 검증이 실패하면 먼저
만든 snapshot으로 같은 writer에 rollback을 시도하고 오류를 표시한다. import는
EventKit event를 만들거나 고치거나 지우지 않는다.

현재 앱이 정상 부팅해 DB를 연 상태에서만 이 import UI를 사용할 수 있다. 시작 시
live DB 자체가 손상되어 open/migration에 실패한 경우의 외부 recovery UI는 Phase 10
범위이며, Phase 9 import가 그 경로까지 해결한다고 보지 않는다.

## Reset Local Data

Reset은 확인 sheet에서 정확히 `RESET`을 입력한 뒤 실행한다. 실행 전에 현재 DB의
자동 ZIP을 `Backups` 폴더에 남기며 자동 backup 생성이 실패하면 reset을 시작하지
않는다.

reset은 한 SQLite transaction에서 다음 current user-data table의 active row를
비운다.

- `provider_pending_operations`
- `task_provider_preferences`
- `provider_sync_cursors`
- `task_bindings`
- `calendar_task_destinations`
- `provider_items`
- `provider_accounts`
- `context_references`
- `event_change_log`
- `event_tasks`
- `event_links`
- `event_contexts`
- `personal_tasks`
- `calendar_set_selection`
- `calendar_set_memberships`
- `calendar_sets`
- `calendar_preferences`
- `calendar_usage_preferences`

GRDB migration history와 schema는 유지한다. 따라서 reset은 빈 새 schema를 다시
만드는 동작이 아니며 EventKit/Exchange 일정 삭제도 아니다.

## 자동 백업 위치와 보관

Import/reset 전 recovery ZIP은 active DB와 같은 Application Support의
`KaosCal/Backups` 아래에 저장한다. 성공 결과에 실제 경로를 표시하며 사용자는
Finder에서 직접 보관·이동·삭제할 수 있다.

작업이 automatic ZIP 생성 뒤 실패하면 그 ZIP이 남을 수 있지만 현재 실패 message가
항상 경로를 표시하지는 않는다. Settings의 active DB 위치에서 인접한 `Backups`
폴더를 확인한다. preflight나 automatic backup 생성 전에 실패했다면 새 recovery ZIP은
없다.

Phase 9의 retention은 수동이다. KaosCal은 자동 backup을 기간이나 개수로 prune하지
않고 storage quota도 관리하지 않는다.

## 문제 해결 경계

- archive가 정확히 두 entry가 아니거나 manifest/hash/schema/integrity/FK 검사가
  실패하면 다른 ZIP을 선택한다. 검사를 우회하지 않는다.
- import/reset 전 notes 저장 실패가 있으면 먼저 Retry로 저장 문제를 해결한다.
- 자동 backup 경로를 만들 수 없으면 import/reset을 실행하지 않는다.
- 앱 시작부터 DB open/migration이 실패했다면 일반 Settings 대신 Phase 10 bootstrap
  recovery를 사용한다. archive preflight가 끝나기 전 기존 파일을 건드리지 않는다.

## 시작 시 DB를 열지 못하는 경우

Phase 10에서는 정상 store가 없을 때 main window와 Settings에 전용 recovery 화면을
표시한다. `Restore From Backup…`에서 직접 만든 current-schema ZIP을 고르면 다음 순서로
진행한다.

1. Phase 9 import와 같은 strict archive/manifest/hash/schema/integrity/FK 검사를 app-private
   staging copy에서 끝낸다. 실패하면 live DB는 byte 단위로 건드리지 않는다.
2. 기존 `kaoscal.sqlite`, `-wal`, `-shm`, `-journal` 중 존재하는 파일을 함께
   `KaosCal/Recovery/Failed-Bootstrap-<UTC>-<UUID>/`로 이동한다. `Recovery`가 directory가
   아니거나 symbolic link면 live 파일을 건드리기 전에 중단한다.
3. 검증된 DB를 live 위치에 설치하고 새 writer로 재오픈·재검증한다.
4. 성공하면 새 `AppState`로 일반 shell을 열고 격리 위치를 표시한다. 격리본은 자동
   삭제하지 않는다.
5. 설치나 재오픈이 실패하면 replacement 파일군을 제거하고 이동한 원본 파일을 전부
   되돌린다. rollback 자체가 불완전하다는 오류면 앱을 종료하고 `Recovery`와 live 폴더를
   모두 보존한다.

이 상태에서는 다음 안전 경계를 따른다.

1. `Reset Local Data`를 시도하거나 Application Support의 SQLite, `-wal`, `-shm`,
   `-journal` 파일을 개별 삭제·교체하지 않는다.
2. KaosCal을 종료한 상태로 오류 문구와 앱 version/build만 기록한다. Event Brief 본문,
   calendar/event identifier, account/email 또는 backup ZIP은 공개 issue에 첨부하지 않는다.
3. 기존 DB와 `Backups` 폴더를 보존한다. 새 설치나 앱 삭제가 local data 복구를 보장한다고
   가정하지 않는다.
4. 호환 backup이 없으면 앱이 제공하지 않는 destructive reset이나 임의 SQLite 편집,
   schema downgrade를 수행하지 않는다. 공개 support 경로가 확정되기 전에는 프로젝트
   소유자에게 비공개로 복구 가능 여부를 확인한다.

자동 테스트는 strict preflight-before-touch, DB+sidecar 격리, successful restore와 설치
검증 실패 뒤 전체 rollback을 다룬다. 실제 signed Release에서 손상 production DB와 file
panel을 사용한 복구, power-loss/crash window와 rollback 자체 실패는 아직 통과하지 않았으므로
그 범위를 자동 결과로 대체하지 않는다.

설계 결정은 [ADR-015](adr/ADR-015-backup-import-reset-safety.md), 검증 절차는
[QA checklist](qa-checklist.md)를 따른다.
