# ADR-015: 로컬 백업·Import·Reset 안전 경계

> 상태: Accepted
> 날짜: 2026-07-12
> 관계: ADR-006의 entitlement 기준과 ADR-008의 Phase 9 migration/recovery 예상을 확장·수정함. Phase 10 bootstrap recovery와 ADR-018의 saved Calendar Set 데이터를 포함함

## 배경

KaosCal의 Event Brief, task, link snapshot, change history, calendar role·usage와 saved
Calendar Set은 로컬
SQLite에만 존재한다. 이 파일을 단순 복사하면 실행 중 WAL과 시점이 어긋날 수 있고,
검증하지 않은 ZIP을 active DB에 덮어쓰면 로컬 데이터 전체를 잃을 수 있다. 반대로
backup/reset 기능이 EventKit을 건드리면 로컬 데이터 관리가 원본 Calendar/Exchange
일정까지 바꾸는 위험한 결합이 된다.

Phase 9는 정상 부팅한 current-schema DB에서 사용자가 명시적으로 export/import/reset
할 수 있는 최소 복구 경로를 제공해야 한다. 손상된 live DB 때문에 앱이 bootstrap
하지 못하는 경우는 다른 실행 경계다.

## 결정

- 대상은 KaosCal local SQLite 전체이며 record-level merge는 하지 않는다. Export,
  import, reset은 EventKit provider write를 호출하지 않는다.
- snapshot과 restore는 실행 중인 단일 `DatabaseWriter`를 통해 SQLite online backup
  API로 수행한다. DB 파일과 WAL/SHM을 filesystem에서 교체하지 않는다.
- sandbox 밖의 수동 export/import는 사용자가 `NSSavePanel`/`NSOpenPanel`에서 명시적으로
  고른 security-scoped URL만 다룬다. 이를 위해 user-selected read/write entitlement를
  사용하며, 자동 recovery backup은 app container의 Application Support에만 저장한다.
- archive는 store-only ZIP이며 root에 `kaoscal.sqlite`, `manifest.json` 두 entry만
  허용한다. manifest는 최대 64 KiB, SQLite는 최대 128 MiB, 전체 archive는 최대
  129 MiB다. 다른 entry, nested path, symlink, duplicate, deflate, encryption,
  data descriptor, ZIP64, multi-disk, extra/comment/attribute, trailing/gapped/overlapping
  payload는 거부한다. 사용자가 다시 압축한 일반 ZIP을 호환 형식으로 간주하지 않는다.
- manifest의 archive format version은 DB schema version과 분리한다. format v1은
  application identifier/version, export 시각, schema identifier/version과 migration
  목록, DB filename/byte count/SHA-256, complete-calendar/linked-snapshot/Event-Brief/
  encryption content flag의 exact key set을 기록한다. 기기 이름과
  `source_machine_name`은 기록하지 않는다.
- import는 archive 구조, manifest format, byte count/hash, migration/schema,
  SQLite integrity와 foreign key를 모두 검증한 뒤에만 진행한다. live restore 후에도
  schema/integrity/FK를 다시 검증한다.
- SHA-256은 archive 안의 manifest와 SQLite entry가 일치하는지 확인하는 integrity
  값일 뿐 서명이나 제작자 인증이 아니다. 사용자가 직접 만든 신뢰 가능한 KaosCal
  backup만 import한다.
- Phase 9 import는 실행 중인 앱의 application identifier와 current schema object,
  migration 목록이 정확히 같은 backup만 허용한다. app version이 달라도 이 계약이
  같으면 import할 수 있지만, 미래 schema의 자동 downgrade나 과거 schema의 자동
  migration은 제공하지 않는다.
- import와 reset은 active DB를 바꾸기 전에 Application Support의 `Backups`에 현재
  DB의 자동 ZIP을 만든다. 자동 backup 실패는 destructive operation을 차단한다.
  restore나 사후 검증 실패는 pre-operation snapshot으로 같은 writer에 rollback을
  시도한다.
- reset은 provider pending/cursor/account/item/binding/destination, context reference,
  event change/task/link/context, personal task, calendar role·usage, saved Set·membership·
  selection의 user row를 child-first 한 transaction에서 지우고 migration history와
  schema를 유지한다.
- ZIP과 SQLite는 KaosCal이 암호화하지 않는 plaintext다. UI는 Event Brief 본문뿐
  아니라 linked title/time/location/identifier와 change snapshot의 원본 notes가
  포함될 수 있음을 명시한다. KaosCal은 계정 credential, Exchange password/MFA,
  OAuth token이나 attendee 전체 목록을 전용 필드로 수집·저장하지 않고 EventKit 전체
  event store도 export하지 않는다. 그러나 사용자 notes/tasks는 검사하거나 redact하지
  않으므로 사용자가 그 본문에 입력한 민감정보는 그대로 backup에 포함될 수 있다.
- 자동 backup retention은 수동이다. Phase 9는 schedule backup이나 자동 pruning을
  수행하지 않는다.
- DB open/migration 실패로 정상 store가 없는 bootstrap recovery는 Phase 10으로
  이월한다. Phase 9의 정상-store Settings import를 그 복구 경로로 과장하지 않는다.
- Phase 10 bootstrap recovery는 정상 `DatabaseWriter`를 만들지 못했을 때만 표시한다.
  선택 archive는 Phase 9와 같은 exact ZIP/manifest/hash/current-schema/integrity/FK
  preflight를 active 파일 변경 전에 통과해야 한다.
- preflight 성공 뒤 기존 `kaoscal.sqlite`, `-wal`, `-shm`, `-journal` 파일군을 같은
  Application Support의 고유 `Recovery/Failed-Bootstrap-*` 폴더로 함께 이동한다. 검증된
  replacement를 live 위치에 설치하고 새 writer로 다시 연 뒤 schema/integrity/FK를
  확인한다. 설치·재오픈이 실패하면 replacement 파일군을 제거하고 이동한 원본 전부를
  되돌린다. `Recovery`가 file 또는 symbolic link면 live 파일을 건드리기 전에 거부한다.
  일부 rollback까지 실패하면 성공으로 표시하지 않는다.
- 성공 뒤에도 격리 파일은 자동 삭제하지 않으며 민감한 local data로 취급한다. 복구
  source와 격리 위치만 사용자에게 알리고 EventKit write는 수행하지 않는다. 현재
  schema와 다른 backup의 migration/downgrade, 임의 SQLite 선택, record merge와
  backup 없는 `Start Fresh`는 이 경로에서 제공하지 않는다.

## 결과

사용자는 Event Brief와 task를 같은 current-schema 계약의 KaosCal에서 읽을 수 있는
ZIP으로 보관하고, active local DB를 안전한 사전 backup 뒤 교체하거나 초기화할 수
있다. Calendar.app과 Exchange 원본은 이 흐름의 소유 범위 밖에 남는다.

엄격한 archive 계약은 임의 SQLite/ZIP import와 record merge를 허용하지 않는다.
plaintext·비인증 archive와 수동 retention 때문에 사용자가 backup 출처, 위치와 수명에
책임을 져야 한다. schema가 바뀐 뒤 과거 backup을 자동 migration하는 기능도 별도
호환성 설계가 필요하다.
Phase 10은 정상 store 없이도 same-schema backup을 선택하는 self-service 재난 복구를
제공한다. 다만 실제 손상 production DB를 이용한 signed Release 복구, power-loss/crash
window와 rollback 자체가 실패하는 filesystem 조건은 별도 manual/fault-injection gate다.
