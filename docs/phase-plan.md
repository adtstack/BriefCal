# Phase Plan

## 진행 원칙

KaosCal은 한 번에 한 phase씩 구현한다.
각 phase는 사용 가능한 작은 데모 단위로 끝나야 하며, 앱은 항상 빌드 가능한 상태여야 한다.

## 현재 진행 상태

- Phase 0: **완료** — 2026-07-10, build/test/ad-hoc signing/window 생성 검증
- Phase 1: **실계정 부분 통과** — 코드·15개 자동 테스트·ad-hoc 서명 검증에 더해 2026-07-11 live FinalRelease에서 full access와 `KAOS-TEST`·`일정`의 writable Exchange 표시를 확인. Calendar.app 시각 round-trip과 read-only fixture는 대기
- Phase 2: **구현·자동 검증 완료 / 실계정 UI 검증 중** — Day/Week/Agenda 공통 범위, 실제 시간·종일 배치, 33개 전체 테스트, Release·서명 build, offscreen 렌더 검증 완료
- Phase 3: **완료** — GRDB v1 migration, 앱 bootstrap, Event Brief/task repository, identity resolver, 파일 재열기·동시 저장, 54-test 전체 회귀, Release·서명 Debug 검증 완료
- Phase 4: **구현·자동·빌드·서명·fixture 시각 검증 완료 / 수동 gate 대기** — notes autosave, event/personal task CRUD·완료·due, typed Task Center, strong-only 원본 탐색 구현; 전체 75 tests와 Release·서명 Debug·strict codesign 통과
- Phase 5: **구현·자동·Release checkpoint / 비반복 EventKit live CRUD 부분 통과** — attendee가 없는 비반복 writable 일정 create/update/delete를 `KAOS-TEST`에서 수행하고 앱 재실행·server fetch·exact cleanup까지 확인. Calendar.app 시각 round-trip, all-day·floating/zoned live gate는 대기
- Phase 6: **구현·자동·Release checkpoint / 반복·이동 live gate 대기** — 명시적 반복 범위, 확인 뒤 write, linked safe move, additive change log, 좁은 session Undo와 안전 차단 경계를 구현했다. 비반복 recurrence 오판 버그를 live gate에서 발견·수정하고 legacy Brief의 좁은 자동 정상화도 추가했으며, live 반복 scope·future split·calendar move는 대기
- Phase 7: **7A~7C 구현 / 비반복 linked delete live 통과 / recurring gate 대기** — lifecycle·After Review, occurrence-aware missing/orphan recovery와 linked original delete를 구현했다. run `20260712-025027-KST`에서 비반복 원본의 Calendar.app·Outlook 제거와 local Brief/task 보존을 확인했으며, recurring `thisEvent`와 crash-window recovery는 대기다.
- Mini month: **구현·집중 자동·210pt offscreen 시각 검증 완료** — locale/firstWeekday/time-zone을 따르는 고정 6×7 civil grid, 독립 월 탐색, 날짜 선택의 기존 range-fetch 연결, today/focused/adjacent 상태와 keyboard·VoiceOver 경계를 구현. 전체 Month 화면과 불완전 fetch 기반 event dot은 범위 밖
- App icon: **구현·호환성·전체 자동·Release 검증 완료** — calendar grid·schedule blocks·Todo check의 원본 표식과 16~1024px alpha slot을 구현. 최초 opaque build를 macOS 14/15 legacy `.icns` 위험으로 제외하고 transparent full-bleed squircle, `.icns` alpha, strict signed Release와 exact bootstrap을 검증했다. Icon Composer layered/dark/tinted variant는 배포 polish로 이월
- Phase 8: **구현·199-test 자동·signed Release·v3 migration 완료 / live UI·shared read-only gate 대기** — local calendar role, role별 virtual Set, source/permission badge, typed read-only reason과 비파괴 duplicate review를 구현했다. 화면 잠금으로 실화면과 shared Viewer는 미검증이다.
- Phase 9: **구현·213-test 자동·signed Release·운영 DB 무변경 완료 / live Settings visual·file-panel·typed `RESET` gate 통과** — healthy current-schema DB의 수동 export, strict two-entry ZIP import, import/reset 전 자동 recovery backup, six-table local reset, rollback 실패 session quarantine과 privacy/storage 설명을 구현했다. 실제 export/import/reset 실행과 손상 live DB의 bootstrap recovery는 별도 gate다.
- Phase 10: 대기

## Phase 표

| Phase | 목표 | 핵심 산출물 | 통과 기준 |
| --- | --- | --- | --- |
| 0 | Repo bootstrap | Xcode project, README, ADR/log, architecture skeleton | 앱이 빌드되고 빈 shell이 뜬다. |
| 1 | Exchange EventKit read-only | full-access flow, Exchange source, events list | Exchange 일정이 Agenda에 표시되고 권한·read-only 상태가 보인다. |
| 2 | Calendar event layout | Day/Week 실제 배치, Agenda 일관성, event cards | 세 화면에서 일정을 클릭하면 inspector가 열린다. |
| 3 | Local context DB | GRDB migrations, repositories, tests | Event Brief와 Task Center 데이터가 SQLite에 저장/조회된다. |
| 4 | Event Brief + Task Center | Before/During/After, personal tasks, inline editing | 일정 작업과 개인 작업을 오늘 목록에서 완료할 수 있다. |
| 5 | Time-safe event editing | create/update/delete, all-day, timezone | Calendar.app에서 원본 변경이 확인되고 시간 의미가 유지된다. |
| 6 | Recurrence + change-safe move | recurrence scope UI, linked calendar move/impact confirmation, change log | 반복 범위와 이동 영향이 명확하며 context가 유지된다. |
| 7 | Lifecycle / After Review | completed/orphaned/after task handling | 종료된 일정의 후속 작업을 처리할 수 있다. |
| 8 | Multi-calendar clarity | source badge, role, read-only explanation | 일정 출처와 권한이 명확히 표시된다. |
| 9 | Backup / settings | export/import, reset local data | DB 백업과 복구가 된다. |
| 10 | Paid beta polish | onboarding, QA, distribution notes | 외부 베타 사용자에게 배포 가능하다. |

## Phase 0: Repo Bootstrap

작업:
- 새 macOS SwiftUI 프로젝트 생성
- 기본 window, sidebar, toolbar shell 생성
- README, docs, ADR 폴더 생성
- implementation log와 Exchange compatibility matrix 생성
- 최소 formatting 규칙 결정

Definition of Done:
- Xcode에서 빌드 성공
- 앱 실행 시 KaosCal shell 표시
- README에 제품 원칙과 실행 방법 존재
- `docs/adr`, `docs/implementation-log.md`, `docs/v1-scope.md`가 존재

완료 증거는 [implementation-log.md](implementation-log.md)의 Phase 0 항목에 기록한다.

## Phase 1: EventKit Read-Only

작업:
- full calendar access permission request 구현
- EventKitProvider 작성
- 오늘 기준 -30일 ~ +90일 이벤트 fetch
- Exchange source·캘린더 목록과 이벤트 목록 표시
- Event store 변경 알림 수신 후 refetch

Definition of Done:
- 권한 허용 시 실제 Exchange Calendar 이벤트 표시
- 권한 거부 시 복구 안내 표시
- 읽기 전용 캘린더와 writable 캘린더 구분
- 시간·종일·반복 occurrence fixture를 compatibility matrix에 기록

현재 판정:
- 자동 검증 통과: fake provider 기반 권한 상태 전이·permissionDenied 정규화, 권한 철회 시 메모리 데이터 제거, -30/+90일 조회 범위, 변경 알림 병합 재조회, 종일 배타 종료일 표시
- 서명 검증 통과: sandbox, Calendar entitlement, full-access usage description
- 실계정 부분 통과: 2026-07-11 FinalRelease run `20260711-1626-B7D2`에서 앱 UI의 `Full calendar access`, `KAOS-TEST`와 `일정`의 Exchange·writable 상태, `KAOS-TEST` 비반복 fixture의 EventKit fetch를 확인했다.
- 수동 검증 대기: 권한 거부·복구 UI, 공유 read-only calendar, all-day·반복 occurrence, Calendar.app 시각 변경 반영
- blocked/이월: 공유 read-only Exchange calendar가 없어 실계정 read-only 판정은 막혀 있다. 구현 checkpoint 뒤 Phase 2는 진행하되 Phase 8 호환성 게이트 전에 해소한다.

## Phase 2: Calendar Event Layout

작업:
- Phase 0의 3-pane shell과 Phase 1의 Agenda를 실제 공통 이벤트 표현으로 정리
- focused period에 맞는 Day/Week/Agenda filtering
- Day view 시간 일정 배치
- Week view 시간 일정 배치와 겹침 column 계산
- all-day lane에 실제 종일·다일 일정 배치
- event card 디자인 적용
- Day/Week 선택 이벤트 state 연결

Definition of Done:
- 일정 클릭 시 오른쪽 패널에 기본 정보 표시
- Today 버튼과 이전/다음 기간 이동 동작
- Day/Week/Agenda에서 시간·종일·출처 표현이 일관됨
- 고밀도에서도 겹침과 클리핑 없음

현재 판정:
- 구현 완료: 24시간 wall-clock grid, 현재 시각선, 종일·다일 span, 자정 횡단 segment, 최소 높이와 겹침 column, 고밀도 가로·종일 세로 scroll
- 공통 의미 완료: Day/Week/Agenda의 반개구간 filtering, 명시적 display calendar/time zone, floating/all-day local components, 반복 occurrence UI identity
- 조회 완료: 초기 오늘 -30/+90일과 visible period가 범위를 벗어날 때의 확장 조회, stale pending 조회 취소, 마지막 loaded range 변경 알림 재조회
- 자동 검증 통과: 전체 33 tests, 0 failures; unsigned Release와 ad-hoc signed Debug build
- 시각 검증 통과: 샘플 15개 일정으로 Week offscreen render에서 calendar color, 3열 overlap, current-time, 자정 횡단, 10행 all-day scroll container 확인
- mini month 보강: Sidebar `List` 위 고정 6×7 날짜 grid, 현재 calendar의 firstWeekday/locale/time-zone, 독립 월 탐색과 날짜 선택을 구현했다. 210pt German-locale offscreen render에서 6행·인접 월·focused/today 표시가 잘리지 않음을 확인했다.
- 수동 부분 통과: 실제 서명 앱에서 권한과 두 writable Exchange calendar를 확인했고, 생성 fixture를 앱 재시작·refetch한 뒤 비반복 상태와 inspector 편집 진입을 확인했다.
- 수동 검증 대기: Day/Week/Agenda 전 화면의 고밀도 선택·scroll·inspector 상호작용과 live all-day·반복 배치
- 실계정 호환성 이월: KC-E2~KC-E4와 공유 read-only Viewer는 각각 해당 phase/Phase 8 gate에서 판정

## Phase 3: Local Context DB

작업:
- GRDB 설치
- Database bootstrap
- migrations 작성
- EventContextRepository 테스트
- PersonalTaskRepository 테스트
- Event identity fingerprint 생성

Definition of Done:
- 앱 재실행 후 Event Brief 유지
- Personal task와 event task가 Task Center query에 함께 표시
- 원본 이벤트 notes에 아무것도 쓰지 않음
- Repository tests 통과

현재 판정:
- 구현 완료: 앱 시작 시 Application Support DB open/migration, 실패 시 in-memory 대체 없이 전역 복구 안내
- schema 완료: `event_contexts`, `event_links`, `event_tasks`, `personal_tasks`와 FK/CHECK/identity unique index
- 저장 완료: 첫 메모·event task에서 context/link 지연 생성, personal/event task CRUD·완료·기한, Task Center 통합 query
- 식별 완료: 강한 ID 관찰 시 snapshot 갱신, weak snapshot/fingerprint는 후보만 반환, zoned instant와 all-day/floating local occurrence 분리
- 안전성 검증 완료: 동시 첫 저장 단일 transaction, UTC millisecond TEXT Date 계약, 파일 재열기와 raw schema constraint 회귀 테스트, hosted XCTest live DB 차단
- 자동 gate 통과: **54 tests, 0 failures**, unsigned Release build, ad-hoc signed Debug build와 strict codesign·entitlement·Info.plist 검증
- 격리 gate 통과: 전체 테스트 전후 direct/sandbox Application Support의 기존 zero-row DB mtime이 바뀌지 않아 test host가 운영 DB를 열지 않음을 확인
- UI 이월: 실제 Event Brief 편집과 Task Center 목록·완료 상호작용은 Phase 4 범위
- 수동 검증 이월: 실제 UI를 통한 앱 종료/재실행 유지와 `KAOS-TEST`의 identifier churn·detached recurrence

## Phase 4: Event Brief UX

작업:
- 오른쪽 패널을 Event Brief 중심으로 재구성
- Before/During/After 섹션 추가
- 체크리스트 CRUD
- notes inline edit
- Task Center today/upcoming/completed 목록
- Personal task CRUD

Definition of Done:
- 일정별 체크리스트 저장
- 완료 체크 상태 저장
- 일정 선택 전환 시 올바른 Brief 로드
- Task Center에서 event-linked task의 원본 일정을 열 수 있음

현재 판정:
- Event Brief 구현: 선택만으로 row를 만들지 않고 Before/During/After inline add·rename·move·complete·delete와 local notes를 제공
- notes 안전성 구현: 700ms debounce, 선택·local mutation·inactive·종료 전 flush, 동일 일정 refresh draft 보존, 실패 draft와 Retry
- Task Center 구현: typed event/personal ID, Today/Upcoming/Completed, 개인 task 생성·rename·due 수정/제거·complete·delete, 날짜·시간대 변경 refresh
- 연결 안전성 구현: candidate/ambiguous 편집 차단, target range fetch 전 이전 range task 취소, strong identifier+occurrence가 하나일 때만 원본 선택
- 권한 구분 구현: read-only/invitation 원본 badge와 `Event Brief · Local editable`을 분리하고 Phase 4에서 EventKit write control을 제공하지 않음
- 자동·빌드·서명 gate 통과: 집중 ContextStore 25 tests와 LocalWorkspace 15 tests에 이어 전체 **75 tests, 0 failures, 0 unexpected**; unsigned Release와 ad-hoc signed Debug build, strict codesign, app sandbox·Calendar entitlement·full-access usage description 확인
- fixture 시각 점검 통과: 실제 DB·EventKit과 분리한 메모리 DB·가짜 provider의 1360×840 offscreen 창에서 초대 원본 안내, local editable badge, Before/During/After·notes, Overdue/Today/No date와 event/personal row의 잘림 없는 핵심 레이아웃 확인
- 수동 gate/이월: 실제 서명 앱 창의 scroll·keyboard focus·popover·삭제 확인, 종료·재실행 유지, `KAOS-TEST` 원본 occurrence 탐색과 Viewer/KC-E6 local-only 동작
- 후속 이월: event task fixed/relative due editor, reminder notification, relink/orphan UI, 원본 일정 편집

## Phase 5: Real Event Editing

작업:
- 새 일정 생성 popover
- 기본 편집: title/time/calendar/location/notes
- 종일 일정 생성/편집
- 시간대 변경과 preserve-local-time/preserve-instant 확인 UI
- 삭제 구현

Definition of Done:
- 생성한 일정이 Calendar.app에 보임
- 수정/삭제가 EventKit에 반영됨
- read-only 일정은 편집 UI 비활성화
- 종일·시간대 fixture가 Exchange compatibility matrix에서 통과

현재 판정:
- 구현 완료: toolbar·`⌘N`과 inspector에서 editor sheet를 열고 title, writable calendar, time/all-day, floating/IANA time zone, location, 원본 notes를 편집한다.
- 쓰기 안전성 구현: full access·writable·비반복·attendee 없는 일정만 허용하고, 같은 store의 강한 identifier로 최신 원본을 다시 찾은 뒤 지원 필드가 외부에서 달라졌으면 중단한다.
- metadata 보존 구현: no-op은 EventKit save를 생략하고 변경 필드만 patch한다. local Event Brief notes/tasks는 `EKEvent.notes`와 분리한다.
- 시간 안전성 구현: 종일 UI 포함 종료↔EventKit 배타 종료, timed 자정 종료 변환, 고정 reference time zone, preserve-local/preserve-instant 미리보기, DST gap/overlap 차단을 적용한다.
- local 연결 보호 구현: pending notes 저장 실패와 weak/ambiguous identity는 editor를 열지 않는다. linked same-calendar 수정은 receipt로 기존 context를 rebind하고 notes/tasks를 보존하며, rebind 실패는 EventKit 부분 성공으로 알린다.
- 명시적 이월: linked calendar 이동은 Phase 6, missing/orphan review와 linked 삭제는 Phase 7B~7C, 반복 create/update/delete와 `EKSpan` 선택은 Phase 6이다. attendee가 있는 회의와 초대 원본은 v1에서 Calendar.app 전용이다.
- 자동·빌드·서명 검증 통과: 전체 **97 tests, 0 failures, 0 unexpected**. create/update/delete AppState 흐름, 제한 정책, stale 오류, linked rebind·사전 차단·부분 성공, transaction rollback, all-day/time-zone/DST 경계를 포함한다. unsigned Release, ad-hoc signed Debug, strict codesign·sandbox·Calendar entitlement·usage description을 확인했고 production DB mtime/size는 테스트 전후 불변이다.
- live 비반복 gate 부분 통과: 2026-07-11 run `20260711-1626-B7D2`에서 recurrence-fix signed Release(CDHash `63ded03a9d704976c4ba45340f2748eda9892382`)의 full access와 `KAOS-TEST`·`일정` writable Exchange 표시를 확인했다. `KAOS-TEST` fixture는 EventKit create, 앱 재실행·refetch, scope 없는 단일 update, 단일 delete를 통과했고 Outlook 서버에서도 처음과 수정 뒤 모두 `singleInstance`·recurrence 없음이었다. 최종 source/destination residue는 `0/0`이며 운영 Context DB도 변하지 않았다.
- 수동 gate 잔여: Calendar.app에서의 시각 create/update/delete round-trip, all-day, floating/zoned 시간대, calendar move와 identifier churn은 대기다. 이 항목 전에는 Exchange Online 전체 지원 통과로 선언하지 않는다.

## Phase 6: Recurrence And Change-Safe Move

작업:
- 반복 occurrence 표시와 기본 recurrence editor
- `이번 일정` / `이번 이후` 영향 범위 선택
- linked calendar 이동과 반복 범위 감지
- calendar 이동·기존 시간 의미 변경과 linked local 영향의 richer confirmation UI
- 연결 항목 리스트 표시
- immutable v1을 보존하는 additive `event_change_log` migration과 변경 기록
- 마지막 linked 비반복 single calendar/time 변경만 되돌리는 session-only undo

Definition of Done:
- 이동 전/후 시간이 로그에 남음
- context_id 유지
- 취소 시 EventKit과 local DB 모두 변경되지 않음
- 반복 occurrence별 Brief가 섞이지 않음
- detached `이번 이후`, 복잡한 rule의 `이번 이후`·rule 변경, attendee meeting은 provider 호출 전에 차단되고 complex `이번 일정` ordinary-field patch는 rule을 보존함
- 초기 Phase 6은 linked future-series write를 전부 차단함. 후속으로 열려면 영향받는 모든 local context를 강하게 reconciliation할 수 있어야 함
- Undo는 앱 재실행·후속 성공 write 뒤 제공되지 않고, 외부 변경 뒤 남은 control도 fresh stale check에서 차단되며, 반복 series나 delete를 되돌리지 않음

현재 구현 판정:
- [ADR-011](adr/ADR-011-recurrence-move-change-log-and-session-undo.md)로 범위와 실패 경계를 확정했다.
- 반복 write와 linked move는 scope·before/after·유지될 local context를 보여 준 뒤 Confirm해야 하며, Cancel은 provider call·local rebind·log append를 수행하지 않도록 구현했다.
- `v2_event_change_log`를 v1 baseline을 수정하지 않는 additive migration으로 구현했고, linked rebind·log와 Undo rebind·restored append를 각각 하나의 SQLite transaction으로 묶었다.
- detached occurrence의 `이번 이후`, 모든 linked `이번 이후`, attendee meeting, complex recurrence의 future/rule 변경은 Calendar.app 또는 안전 안내로 보낸다. complex recurrence의 `이번 일정` ordinary-field patch는 rule을 보존한다. Phase 6 checkpoint 당시 linked delete는 Phase 7C까지 차단했으며 현재는 Phase 7C의 별도 final review 경로만 허용한다.
- Phase 6의 **121-test 구현 checkpoint**, 122-test read-only gate와 132-test legacy compatibility checkpoint, Phase 7A의 145-test checkpoint, mini month·AppIcon의 154-test checkpoint, Phase 7B의 175-test, Phase 7C의 189-test와 Phase 8의 199-test Release checkpoint를 역사적 증거로 보존한다. 현재 최신 suite는 Phase 9의 **213 tests executed, 212 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**이며 result bundle은 `/private/tmp/KaosCalPhase9FinalTests-20260712-1535.xcresult`다.
- live gate에서 EventKit이 비반복 `EKEvent`에도 `occurrenceDate == startDate`를 제공할 수 있어 반복 badge와 scope를 잘못 요구하는 문제를 발견했다. 반복 소속은 `hasRecurrenceRules || isDetached`만으로 판정하고, 비반복 display identity의 `occurrenceDate`는 `nil`로 정규화하도록 수정했다.
- transparent AppIcon 최종 build-only Release `/private/tmp/KaosCalIconCompatRelease/Build/Products/Release/KaosCal.app`는 CDHash `bc2ddd83c9d7f5e1bfd62241b0e02e63b23308b6`로 strict codesign, hardened runtime, app sandbox, Calendar entitlement, `AppIcon.icns` alpha를 통과했다. 전체 154-test 결과는 `/private/tmp/KaosCalAppIconCompatFinal.xcresult`다. 실계정 run은 recurrence-fix artifact에 계속 귀속하고 AppIcon 작업에서는 fixture write를 실행하지 않았다.
- 2026-07-11 FinalRelease EventKit run `20260711-1626-B7D2`에서 full access, 두 writable Exchange calendar, `KAOS-TEST` 비반복 create→앱 재실행/refetch→scope 없는 update→single delete를 확인했다. 서버 item은 생성·수정 뒤 모두 `singleInstance`·recurrence 없음이었고 source/destination marker residue는 `0/0`이었다.
- 이전 Outlook connector run `20260711-1512-7C4E`의 source create/fetch/update, destination independent write, 시간대·유한 반복 `this_instance`, exact cleanup checkpoint는 유지한다. actual cross-calendar move·all-day는 당시 도구 입력이 없어 미검증이고 `this_and_following`은 mutation 전에 거부됐다.
- Calendar.app 시각 round-trip, live all-day, 실제 반복 `이번 일정`/`이번 이후`·future split, `KAOS-TEST`→`일정` calendar move는 아직 대기다. 현재 결과를 Exchange Online 전체 지원 통과로 합치지 않는다.

## Phase 7: Lifecycle / After Review

작업:
- scheduled/completed/cancelled/orphaned lifecycle 상태 구현
- moved는 change log로 기록
- 일정 종료 후 After Review 표시
- 후속 작업만 오늘 목록에 남기기
- 원본 일정 삭제 감지 시 orphaned 표시

Definition of Done:
- 종료된 일정의 After task 처리 가능
- 삭제된 원본 일정의 Brief가 보관됨
- 사용자가 보관/재연결/삭제 선택 가능

현재 구현 판정:
- **Phase 7A 완료**: active link의 occurrence별 유효 종료를 기준으로 `scheduled ↔ completed`를 갱신한다. `now == end`가 완료 경계이며, 종일은 배타 종료일, floating은 저장 civil components를 현재 표시 calendar에서 재구성한다.
- 완료 일정은 Event Brief에 `Event ended` banner와 After Review 안내를 표시한다. Today/Upcoming의 열린 Before/During은 DB에서 삭제하거나 자동 완료하지 않고 projection에서만 제외하며, 미완료 After만 유지한다.
- Task Center에 `After Review` 필터를 추가했다. completed context의 미완료 After만 표시하고 personal task와 완료 task는 제외한다. Completed 목록은 기존 모든 section 기록을 보존한다.
- 시간 reconciliation은 `cancelled`/`orphaned` 또는 non-active link를 덮어쓰지 않고, 관찰에서 파생한 완료에는 change log를 만들지 않는다. 미래로 이동한 active 일정은 다시 scheduled가 될 수 있다.
- 반복 write 뒤 동일 identifier를 공유하는 다른 occurrence를 잘못 선택할 수 있던 회귀를 함께 수정했다. post-write selection은 전체 exact display ID를 먼저 찾고, 반복 fallback은 같은 calendar와 같은 civil/instant occurrence anchor까지 요구한다.
- [ADR-012](adr/ADR-012-lifecycle-after-review-and-orphan-confirmation.md)에서 7A~7C의 lifecycle·recovery·linked delete 안전 경계를 확정했다.
- **Phase 7B 완료**: 일반 구간 fetch 부재는 삭제 증거로 쓰지 않는다. 저장 link 기반 strong occurrence-aware 전용 lookup의 첫 명시적 `notFound`는 link를 `missing`으로만 표시하고, 별도 `Check Again`의 두 번째 명시적 `notFound` 뒤에만 `Keep as orphan`, exact-candidate `Relink`, `Delete local Brief`를 제공한다. provider error, weak/ambiguous candidate, 권한 문제와 보수적 recurring `inconclusive`는 부재 증거로 세지 않는다.
- 어느 calendar에서든 strong identifier seed의 recurrence/occurrence shape가 저장 anchor와 맞지 않으면 `notFound`가 아니라 inconclusive다. 살아 있는 series의 한 occurrence가 삭제된 경우와 검색 범위 밖으로 이동한 detached occurrence는 EventKit bounded lookup만으로 구분할 수 없어 자동 missing/orphan을 선언하지 않고 manual exact relink로 보낸다.
- 재연결은 선택 후보를 provider에서 마지막으로 exact 검증하고 expected-link 전체 상태를 CAS로 확인한 뒤 link/context/change log를 한 transaction에서 갱신한다. local notes/tasks는 보존하며, local 삭제는 SQLite FK cascade만 사용하고 EventKit create/update/delete를 호출하지 않는다. Task Center의 `Local Event Briefs`에서 active notes-only와 missing/orphan Brief도 복구할 수 있다.
- 열린 recovery sheet는 background strong recovery나 external local deletion 뒤 fresh Brief 상태와 reconcile해 stale destructive action을 닫는다. recovery sheet의 local notes는 줄 제한 없이 읽고 복사할 수 있다.
- Phase 7B 최종 build-only Release `/private/tmp/KaosCalPhase7BFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `f3b30718434641dbbd2dbec90f82581342d47506`은 strict codesign, hardened runtime, sandbox, Calendar entitlement, XCTest/get-task-allow 부재를 통과했다. exact artifact가 1482×931 onscreen 창을 만들고 정상 종료 뒤 process 0이었으며 test·bootstrap 전후 production DB는 불변이다.
- **Phase 7C 구현·fake-only 자동 checkpoint 완료**: active Brief의 saved link, notes/tasks/history와 snapshot을 read-only로 준비하고 별도 `Delete Original & Keep Brief` Confirm 직전 다시 CAS한다. Confirm 전 provider/local write는 0회다.
- successful delete receipt 뒤 한 SQLite transaction에서 context `cancelled`, link `orphaned`, 이전 available Undo supersede와 saved-link unavailable `cancelled` log를 저장한다. before/after payload는 같고 `originalNotes`는 nil/unavailable이며 local notes/tasks와 context ID를 유지한다. deleted-original UI는 상태쌍에 더해 현재 link 세대에 이 log가 있고 뒤따르는 `relinked`가 없는지 `(created_at, rowid)`로 확인한다. nonrecurring log scope는 `single`, recurring은 `this_event`; Delete Undo와 Phase 7C migration은 없다.
- receipt 모순, local CAS/log 실패나 EventKit-local 사이 crash는 자동 원본 복원 없이 no-retry 부분 성공으로 처리한다. local transaction은 rollback되고 Brief/notes/tasks가 남아 Task Center recovery로 이어진다.
- linked `futureEvents`, attendee meeting/invitation 원본 삭제는 계속 차단한다. 후속 run `20260712-025027-KST`에서 비반복 `single`의 Calendar.app/Outlook 제거와 local 보존은 통과했지만 recurring `thisEvent`, one-off exception과 crash recovery는 **live pending**이다.
- Phase 7C 신규 회귀 총 14개를 포함한 전체 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**를 통과했다. result bundle은 `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`다.
- 최종 build-only Release `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6b1da198f969cb033946fdb72b2b2e46392310f2`는 strict codesign, hardened runtime, app sandbox, Calendar entitlement, usage description을 통과했고 get-task-allow·XCTest plug-in/link가 없다. exact binary를 production DB 차단 환경으로 5초 이상 기동한 뒤 종료해 process 0과 direct/sandbox DB hash·mtime·size 및 WAL/SHM 부재 불변을 확인했다. computer-use runtime이 없어 이번 checkpoint에는 onscreen tree/크기 증거를 포함하지 않는다.

## Phase 8: Multi-Calendar Clarity

작업:
- calendar role 설정
- source badge 표시
- read-only reason 표시
- calendar sets 초안
- 중복 후보 감지 초안

Definition of Done:
- 각 일정이 Work/Personal/Subscription 등 역할을 표시
- 읽기 전용 일정은 왜 수정 불가인지 설명
- 비슷한 시간/제목의 후보 감지

현재 구현 판정:
- `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`를 EventKit raw model과 분리된 local projection으로 구현했다. subscribed/birthdays만 현재 source에서 `Subscription`으로 추론하고 다른 source는 `Other`로 둔다. 사용자가 고른 explicit role만 sparse `calendar_preferences` row로 저장한다.
- `All`과 역할별 virtual Set은 Day/Week/Agenda visibility만 좁힌다. raw fetch, Event Brief observation, Task Center, relink와 writable destination은 숨기지 않으며 custom saved Set은 Phase 9 이후로 이월한다.
- Sidebar·Agenda·Day/Week timed/all-day card·Inspector에는 role, calendar/source/account와 permission을 연결했고 editor에는 destination role을 표시한다. Task Center는 저장 calendar identifier로 calendar/source/role만 투영한다. invitation→attendee→subscription→birthdays→provider read-only의 typed reason은 해당 원본 UI와 write preflight가 함께 사용한다.
- duplicate는 서로 다른 calendar에서 정규화 제목과 timed start/end 각 15분 이내 또는 같은 all-day civil range가 맞는 항목만 후보로 만든다. fetch마다 index를 한 번 계산하고 card는 O(1) 조회한다. strong same occurrence는 제외하며 merge·hide·delete·EventKit write는 제공하지 않는다.
- additive `v3_calendar_clarity`와 `CalendarRoleRepository`를 구현했다. v1/v2→v3, CHECK, sparse row, upsert/reopen/delete/reset, 역할 변경·Set·duplicate에서 provider write 0회를 자동 검증했다.
- 최종 전체 **199 tests executed, 198 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**. result bundle은 `/private/tmp/KaosCalPhase8FinalTests-20260712-1415.xcresult`다.
- Release `/private/tmp/KaosCalPhase8FinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6c595445dadfb60588410329222557d00865c222`는 strict codesign·hardened runtime·sandbox·Calendar entitlement를 통과했고 get-task-allow·XCTest가 없다.
- exact Release 정상 bootstrap으로 sandbox 운영 DB를 v2→v3로 migration했다. integrity `ok`, FK violation 0, `calendar_preferences` 0행, 기존 v1/v2 table count·SHA3 불변, 종료 뒤 WAL/SHM 부재와 process 0을 확인했다. 사전 copy는 `/private/tmp/KaosCalPhase8MigrationPreflight-20260712-1406/kaoscal-pre-v3.sqlite`에 있다.
- 화면 잠금 때문에 role/source가 긴 Sidebar·Inspector, 44pt 고밀도 card와 VoiceOver 순서는 실화면 확인하지 못했다. shared read-only Exchange fixture도 없어 provider-reported reason의 live gate는 **manual pending**이다. 이 두 항목을 자동·Release 통과로 대체하지 않는다.

## Phase 9: Backup / Settings

작업:
- DB export/import
- reset local context
- 저장 위치 표시
- privacy copy 작성
- manual backup UX

Definition of Done:
- zip export 생성
- 새 DB에 import 성공
- 원본 캘린더 이벤트 삭제 없이 KaosCal 데이터만 삭제 가능

현재 구현 판정:
- 정상 부팅해 `v3_calendar_clarity`까지 migration된 file-backed DB만 Local Data 작업을 연다. pending notes를 먼저 flush하고 저장 실패, 다른 local-data operation, editor mutation/recovery가 진행 중이면 export/import/reset을 시작하지 않는다.
- 수동 export는 live `DatabaseWriter`의 SQLite online snapshot을 사용한다. store-only ZIP root에는 `kaoscal.sqlite`와 `manifest.json` 두 entry만 있으며 archive format version을 DB schema와 분리하고 app/export metadata, schema와 migration 목록, DB byte count·SHA-256을 기록한다. 기기 이름은 기록하지 않는다. manifest 64 KiB, DB 128 MiB, archive 129 MiB 상한을 두고 deflate/encryption/data descriptor/ZIP64/multi-disk와 재압축된 archive를 거부한다.
- import는 archive entry/encoding, manifest format, byte count/hash, schema/migration, SQLite integrity와 foreign key를 모두 검사한다. active DB를 바꾸기 전에 Application Support `Backups`에 자동 ZIP을 남기고, 같은 writer에 hot restore한 뒤 다시 검증한다. 실패하면 active DB를 유지하거나 사전 snapshot rollback을 시도한다.
- reset은 정확한 `RESET` 확인 뒤 사전 자동 ZIP을 만들고 `event_change_log`, `event_tasks`, `event_links`, `event_contexts`, `personal_tasks`, `calendar_preferences`의 active row만 한 transaction에서 지운다. GRDB migration history와 schema는 유지한다.
- Settings는 DB 위치와 Finder 열기, linked event metadata·original-notes snapshot 포함 가능성, complete calendar record/account credential/Exchange password 전용 필드 비포함과 plaintext 위험을 표시한다. KaosCal은 credential/token과 attendee 전체 목록을 전용 필드로 수집하지 않고 EventKit 전체 event store도 export하지 않지만, 사용자 notes/tasks를 redact하지 않으므로 본문에 입력한 민감정보는 포함될 수 있다는 경계도 UI와 backup 문서에 명시한다.
- export/import/reset은 EventKit write를 호출하지 않는다. 자동 backup은 사용자가 직접 관리하며 schedule·retention pruning·자동 삭제를 하지 않는다.
- SHA-256은 archive byte integrity일 뿐 제작자 인증이 아니다. 실행 중인 앱과 application identifier·current schema object·migration 목록이 정확히 같은 신뢰 가능한 backup만 import하며 schema upgrade/downgrade는 지원하지 않는다.
- DB open/migration 실패로 정상 store가 없는 시작 상태에서 corrupt live DB를 교체하는 recovery UI는 Phase 10으로 이월한다. 상세 계약은 [backup-restore.md](backup-restore.md)와 [ADR-015](adr/ADR-015-backup-import-reset-safety.md)를 따른다.
- 최종 전체 **213 tests executed, 212 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**이며 result bundle은 `/private/tmp/KaosCalPhase9FinalTests-20260712-1535.xcresult`다. core 8개와 AppState 6개 Phase 9 집중 테스트에는 strict archive/schema/destination, same-writer import/reset recovery, rollback 실패 quarantine, file-backed 620×620 Settings render와 fake provider write 0회가 포함된다.
- signed Release `/private/tmp/KaosCalPhase9FinalRelease-20260712-1535/Build/Products/Release/KaosCal.app`, CDHash `4f6eb184110ca317a440c5d640cf0670e4c42753`는 strict codesign·hardened runtime, sandbox·Calendar·user-selected read/write entitlement와 usage description/AppIcon을 통과했고 get-task-allow·XCTest가 없다.
- exact Release는 1512×949 visible window를 만들고 종료됐다. 전체 test와 두 차례 exact bootstrap 전후 direct/sandbox 운영 DB의 mtime·size·SHA-256, integrity/FK, WAL/SHM/journal 부재가 불변이고 최종 process는 0이다. 후속 live run `20260712-1616-KST`에서 같은 Release의 620×652 Settings 전체 scroll, 880×448 Export/Import panel, privacy/storage copy와 `RESET` 입력 뒤 destructive button 활성화를 확인했다. 모든 panel과 reset sheet는 취소했으며 실제 export/import/reset은 실행하지 않았다. 종료 뒤 운영 DB와 sidecar 부재는 다시 불변이고 process는 0이다.

## Phase 10: Paid Beta Polish

작업:
- 온보딩 polish
- crash-safe error states
- keyboard shortcuts
- empty states
- direct distribution 준비
- license placeholder

Definition of Done:
- 외부 테스트 사용자가 설명 없이 설치, 실행, 권한 허용, 핵심 데모를 수행할 수 있음

## 작업 프로토콜

모든 phase 작업은 아래 순서를 따른다.

1. 기존 파일을 먼저 읽는다.
2. 목표 범위를 한 문장으로 고정한다.
3. 가장 작은 유용한 변경을 구현한다.
4. 가능한 빌드 또는 테스트를 실행한다.
5. 로직 변경에는 테스트를 붙인다.
6. 아키텍처나 동작이 바뀌면 ADR, v1 scope, QA, implementation log를 업데이트한다.
7. 변경 파일과 실제 검증 결과를 요약한다.
8. 다음 phase 또는 다음 작업 하나만 제안한다.
