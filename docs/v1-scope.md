# V1 Scope

> 상태: Accepted
> 마지막 갱신: 2026-07-12
> 우선순위: 이 문서는 이전 문서와 충돌할 때 최신 ADR을 따라 해석한다.

## 한 줄 제품 정의

KaosCal은 macOS Calendar의 일정을 Day, Week, Agenda에서 관리하고, 일정 맥락과 개인 할 일을 로컬 Task Center에서 함께 처리하는 macOS-first calendar다.

## v1 필수 범위

| 영역 | 제공 범위 | 인수 기준 |
| --- | --- | --- |
| 플랫폼 | macOS 14 이상, Apple Silicon 우선 | Xcode에서 빌드·실행하고 권한 상태를 안전하게 처리한다. |
| 캘린더 연결 | macOS Calendar에 구성된 Exchange Online 계정을 EventKit으로 사용 | 별도 Microsoft OAuth/Graph 없이 Exchange source와 calendar를 읽는다. |
| 화면 | Day, Week, Agenda, mini month, 3-pane inspector | 같은 이벤트가 세 화면에서 같은 시간·role·출처·편집 가능 상태로 보인다. |
| Multi-calendar clarity | local calendar role, role별 virtual Set, typed read-only reason, possible duplicate review | role 변경은 EventKit 원본을 바꾸지 않고, duplicate는 자동 병합·숨김·삭제하지 않은 채 후보로만 보인다. |
| 일정 | 시간 일정, 종일 일정, 시간대가 있는 일정과 floating 일정 | 종일은 날짜 범위로, 시간 일정은 시간대 의미를 잃지 않고 표시·편집한다. |
| 반복 | 모든 occurrence 표시, 손실 없이 표현 가능한 기본 일·주·월·년 규칙 생성/편집, 이번 일정·이번 이후 범위 선택 | 반복 Brief가 다른 occurrence에 섞이지 않고, scope Confirm 전에는 write하지 않으며, 서버가 거부한 변경은 원본을 훼손하지 않는다. |
| Event Brief | Before/During/After 작업, 로컬 메모, 원본 이동·시간·반복 변경 이력 | EventKit notes를 변경하지 않고 앱 재실행 뒤에도 유지된다. |
| Task Center | 이벤트 작업을 모아 보고, 이벤트에 연결되지 않은 가벼운 개인 작업을 추가 | 오늘·예정·After Review·완료 목록에서 작업 출처와 연결 일정을 명확히 보여 준다. |
| Local Data | 수동 ZIP export/import, import/reset 전 recovery backup, local-only reset | archive와 DB를 엄격히 검증하고 Calendar/Exchange 원본을 바꾸지 않은 채 KaosCal local data를 복원·초기화한다. |
| 안전성 | read-only 구분, recurrence/move impact 확인, 좁은 session Undo, orphan 보존, 백업/복원 | 원본 일정과 KaosCal 데이터의 삭제·복원이 서로 영향을 주지 않고 unsafe future-series write를 사전에 차단한다. |

현재 구현 단계는 범위 자체와 구분한다. Phase 5의 비반복 원본 편집 위에 Phase 6의 기본 반복 규칙, 명시적 scope, impact Confirm, linked safe move, additive change log, session-only Undo를 구현했고, Phase 7A에서 occurrence 종료 기반 scheduled/completed, After Review와 완료 일정 후속 작업 projection을 추가했다. Phase 7B는 전용 occurrence-aware lookup, 두 번의 명시적 `notFound`, local Brief 보관·재연결·삭제를 구현했다. Phase 7C는 active linked 원본의 saved-link/notes/tasks impact review와 별도 final Confirm, successful delete receipt 뒤 `cancelled + orphaned` local Brief 보존, unavailable cancellation provenance와 no-Undo partial-success 경계를 구현했다. deleted-original 표시는 현재 link 세대의 KaosCal deletion log를 요구하고 이후 `(created_at, rowid)`상 더 늦은 relink가 과거 provenance를 무효화한다. Phase 7C는 새 schema를 요구하지 않았다. 다만 살아 있는 반복 series의 **외부** 단일 occurrence 삭제는 범위 밖 detached move와 EventKit read로 구분할 수 없어 automatic orphan이 아니라 manual exact relink로 남기고, KaosCal이 직접 시작한 `thisEvent` 삭제만 successful receipt로 exact finalize한다.

Phase 8은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other` role, explicit role만 저장하는 additive `v3_calendar_clarity`, `All`과 role별 virtual Set, typed restriction과 non-mutating duplicate projection을 구현했다. subscribed/birthdays만 현재 source가 있을 때 `Subscription`으로 추론하고 나머지 source는 용도를 추측하지 않는다. source가 사라지고 exact explicit override도 없으면 account type snapshot을 재해석하지 않고 `Other`로 표시한다. role 변경은 Calendar.app·EventKit 원본을 바꾸지 않는다. virtual Set은 Day/Week/Agenda visibility만 좁히고, possible duplicate는 fetch 시 한 번 계산한 index에서 정규화 title과 보수적 시간 범위가 같은 다른 calendar 후보를 O(1) 조회할 뿐 자동 merge·hide·delete하지 않는다. Inspector restriction과 AppState write preflight는 같은 typed reason을 사용한다. 고정 6×7 mini month 날짜 탐색기와 macOS 14/15 legacy `.icns` alpha를 포함한 16~1024px AppIcon도 구현했다.

Phase 9은 healthy current-schema DB의 수동 ZIP export/import와 local reset을 구현했다.
archive는 store-only이며 `kaoscal.sqlite`와 `manifest.json`만 허용하고, format version을
DB schema와 분리해 migration 목록·byte count·SHA-256을 검증한다. manifest 64 KiB,
DB 128 MiB, archive 129 MiB 상한과 strict classic-ZIP 계약을 적용한다. SHA-256은
제작자 서명이 아니며, 실행 중인 앱과 application identifier·current schema·migration
목록이 정확히 같은 신뢰 가능한 backup만 import한다. 과거 schema 자동 migration과
미래 schema downgrade는 v1 범위가 아니다.

Import/reset은 active DB를 바꾸기 전에 `Backups`에 recovery ZIP을 남기며 같은 live
SQLite writer에서 restore/reset한다. reset은 여섯 user-data table만 비우고 migration
history는 유지한다. ZIP은 linked event metadata와 change snapshot의 original-notes
snapshot을 포함할 수 있는 plaintext다. KaosCal은 계정 credential/token이나 attendee
전체 목록을 전용 필드로 수집하지 않고 전체 EventKit event store도 export하지 않지만,
사용자 notes/tasks는 검사·redact하지 않으므로 본문에 입력한 민감정보는 포함될 수 있다.
모든 Local Data 작업은 EventKit write를 하지 않는다.

손상 live DB가 bootstrap에 실패한 상태의 recovery, schedule backup과 자동
retention/pruning은 Phase 10 또는 후속 범위다. custom saved calendar set, color/name
override와 Icon Composer variant도 배포 polish로 남아 있다. 상세 계약은
[backup-restore.md](backup-restore.md)와
[ADR-015](adr/ADR-015-backup-import-reset-safety.md)를 따른다. 자동 회귀와 signed
Release의 정확한 checkpoint는 phase plan과 implementation log에 분리 기록한다.

2026-07-11 live FinalRelease run `20260711-1626-B7D2`에서 full access, `KAOS-TEST`·`일정`의 writable Exchange 표시, `KAOS-TEST` 비반복 create→앱 재실행/refetch→scope 없는 update→single delete를 확인했다. 서버에서도 생성·수정 뒤 모두 `singleInstance`이고 recurrence가 없었으며 source/destination residue는 `0/0`이었다. EventKit이 단일 일정에도 `occurrenceDate == startDate`를 줄 수 있는 실제 동작은 반복 소속을 `hasRecurrenceRules || isDetached`로만 판정하고 비반복 occurrence date를 `nil`로 정규화하는 회귀 수정에 반영했다. 과거 오분류 build가 만든 Brief는 강한 식별자와 전체 snapshot/anchor가 정확히 일치할 때만 `single:v1`로 런타임 정상화하며, weak match는 자동 연결하지 않는다. 후속 Phase 7C live gate에서 비반복 linked original delete, Calendar.app/Outlook 원본 부재, local Brief·Notes·section task 보존과 deletion provenance를 확인했다. 반복 `thisEvent` mutation과 retained local Brief cleanup UI는 macOS session lock으로 미검증이며 비반복 결과로 대체하지 않는다.

Calendar.app 시각 round-trip, live all-day, 반복/future split, calendar move, 외부 삭제 동기화 지연과 shared read-only Exchange permission reason은 각각 독립 gate다. Phase 8 role/source/restriction/duplicate의 긴 문구·고밀도 화면도 session lock으로 live visual 검증하지 못했다. 따라서 코드 구현을 Exchange Online 전체 지원 또는 시각 gate 통과로 선언하지 않는다.

복잡한 recurrence는 rule을 보존한다. 선택 occurrence의 일반 필드는 `이번 일정`에서 recurrence rule을 쓰지 않는 조건으로 편집할 수 있지만, `이번 이후`와 rule 자체 변경은 Calendar.app 전용이다.

## Exchange 지원 경계

- 지원 문구는 **“macOS Calendar에 구성된 Exchange Online 캘린더”**로 한정한다.
- 수정 가능 여부는 계정 종류가 아니라 EventKit이 보고하는 캘린더별 권한을 따른다.
- shared read-only Exchange의 구체 ACL 원인은 추측하지 않고 typed `providerReadOnly`로 설명한다. 실제 shared read-only fixture·화면 표시는 별도 live gate 미검증이다.
- 온프레미스 Exchange는 별도 호환성 검증 전까지 지원을 약속하지 않는다.
- KaosCal은 Microsoft Graph, EWS, 자체 동기화 엔진, 계정 자격 증명을 사용하지 않는다.
- macOS permission, EventKit source/writable, 앱 CRUD, 서버 fetch, Calendar.app 시각 round-trip은 각각 별도 증거로 관리한다.

## 초대 일정 정책

초대받은 일정과 사용자가 주최했더라도 참석자가 있는 meeting은 표시하고 로컬 Event Brief와 작업을 붙일 수 있다. 다만 v1에서는 RSVP, 참석자, 주최자, 원본 제목·시간·삭제 변경을 제공하지 않는다. 사용자는 Calendar.app에서 해당 동작을 수행한다.

## Task Center 정책

Task Center는 프로젝트 관리 도구가 아니다.

- Event task: 하나의 Event Brief에 연결된 Before/During/After 작업
- Personal task: 일정 없이 빠르게 적는 개인 작업
- 제공하지 않는 것: 프로젝트, 팀 공유, Kanban, 우선순위 매트릭스, Apple Reminders·Exchange Tasks 동기화

## 명시적 제외 범위

- AI 자동 스케줄링, 자동 재배치, 자동 수락
- 모바일 앱, 서버 기반 KaosCal Cloud, 사용자 계정
- 직접 Google/Microsoft/CalDAV 동기화
- 초대 일정 RSVP·참석자 관리
- 복잡한 반복 규칙을 KaosCal이 안전하게 표현할 수 없을 때의 강제 수정
- detached occurrence의 `이번 이후`, 강한 context reconciliation 계획이 없는 linked future-series write
- 반복 series·detached occurrence·delete의 일반 Undo와 앱 재실행 뒤 Undo
- 임의 이름 saved Calendar Set, calendar별 visibility·role color/name override
- possible duplicate의 자동 merge·hide·delete 또는 EventKit 원본 변경
- backup record-level merge, schedule backup, 자동 retention/pruning
- 정상 DB bootstrap 이전의 손상 live DB recovery UI

## 범위 변경 규칙

새 기능이 필요하면 먼저 다음을 확인한다.

1. Day/Week/Agenda, Event Brief, Task Center 중 하나를 더 신뢰성 있게 만드는가?
2. Exchange/EventKit의 실제 동작을 호환성 문서로 검증할 수 있는가?
3. 원본 일정과 로컬 데이터의 소유권 경계를 유지하는가?
4. ADR, QA, 구현 로그를 같은 변경에서 갱신했는가?
