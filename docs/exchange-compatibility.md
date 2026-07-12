# Exchange Compatibility

> 현재 phase·최신 suite·열린 gate 요약: [Current Status](current-status.md) 참조
> 제품 대상: macOS Calendar에 구성된 Exchange Online
> 현재 테스트 환경: backend 종류 미확인. Outlook connector run `20260711-1512-7C4E`에서 `KAOS-TEST`(source)·`일정`(destination)이 각각 exact-name 1개, editable, distinct, same owner로 관찰됐고, signed FinalRelease/EventKit run `20260711-1626-B7D2`에서 두 calendar의 비반복 CRUD를 확인했다. Phase 7C run `20260712-025027-KST`에서는 exact signed Release의 full access와 두 calendar의 `Exchange`·writable 표시, linked 비반복 원본의 KaosCal→Calendar.app→Outlook 삭제 및 local Brief 보존을 확인했다. backend의 Exchange Online 판정 증거는 아니다.
> 마지막 갱신: 2026-07-12

## 지원 선언 기준

KaosCal은 추측으로 Exchange 기능을 지원한다고 선언하지 않는다. 아래 매트릭스에서 실제 macOS·Exchange 조합으로 통과한 항목만 베타 지원 범위에 넣는다.

| 기능 | 현재 테스트 환경 | 상태 | 증거 |
| --- | --- | --- | --- |
| full calendar access | signed FinalRelease에서 full access와 재실행 후 EventKit refetch 확인 | 로컬 통과 | run `20260711-1626-B7D2`, Phase 7C run `20260712-025027-KST`; 권한 철회·재허용 회귀는 별도 |
| Exchange source·calendar 식별 | 서버 connector에서 두 exact-name calendar를 구분하고 FinalRelease sidebar에서 둘 다 `Exchange`로 표시 | 서버·EventKit 통과 / backend 미판정 | `KAOS-TEST`·`일정`을 distinct calendar로 확인. 이 표시만으로 Exchange Online backend라고 추론하지 않음 |
| editable calendar 확인 | FinalRelease에서 두 calendar 모두 lock 없이 writable로 표시 | 서버·EventKit 통과 | `KAOS-TEST` 실제 create/update/delete 통과; `일정`은 이번 local run에서 mutation하지 않음 |
| read-only 구분 | typed invitation·attendee·subscription·birthdays·provider reason과 write preflight 자동 통과 | 구현 통과 / live blocked | Viewer calendar 미준비. Exchange ACL을 추측하지 않고 EventKit provider read-only로 설명하며 실화면 gate는 대기 |
| local role·virtual Set | Work/Personal/Family/Shared/Subscription/Other sparse local role과 role별 Day/Week/Agenda filter 자동 통과 | 로컬 구현 통과 / live UI 대기 | EventKit write 0회. source가 사라지고 explicit role도 없으면 Other; custom saved Set은 후속 범위 |
| possible duplicate review | cross-calendar normalized title·15분 timed/same all-day range candidate index 자동 통과 | 로컬 구현 통과 / live UI 대기 | 자동 merge·hide·delete 없음. 실제 Exchange 일정의 dense card/Inspector 표시는 session lock으로 미확인 |
| 시간 일정 조회 | 서버 fixture와 signed FinalRelease create·재실행·refetch 확인 | 서버·EventKit 통과 | local fixture가 재실행 후에도 단일 일정으로 표시되고 서버에서 `singleInstance`·recurrence null·UTC 정규화 확인 |
| 비반복 일정 생성 | FinalRelease에서 `KAOS-TEST`에 실제 생성 | 서버·EventKit 통과 / Calendar.app 대기 | 서버에서 단일 instance와 recurrence null 확인; Calendar.app visual round-trip은 미실행 |
| 비반복 일정 수정 | FinalRelease에서 동일 fixture를 한 번 수정하고 refetch | 서버·EventKit 통과 / Calendar.app 대기 | 재실행 후 잘못된 반복 badge/scope 없이 single update, 서버 recurrence null 유지 |
| 비반복 일정 삭제 | FinalRelease에서 single delete, Phase 7C에서 linked single delete 실행 | 서버·EventKit·Calendar.app 통과 | run `20260711-1626-B7D2`의 일반 single cleanup과 run `20260712-025027-KST`의 linked 원본 삭제·Calendar.app exact title `결과 없음`; 서버 residue 0 |
| calendar 간 이동 | local Brief 없는 move와 linked safe move·impact Confirm·context rebind 자동 통과 | 미검증 | connector에 move API가 없어 `KAOS-TEST`→`일정` actual move를 실행하지 않음; create+delete를 move 증거로 사용하지 않음 |
| 종일·다일 일정 조회 | 자정/`23:59:59` raw end 정규화, 배타 범위·all-day span unit 통과 | 실계정 대기 | connector create schema에 `isAllDay`가 없어 server run도 수행하지 않음 |
| 종일 일정 생성·편집 | 포함 종료↔배타 종료, 자정 변환, reference time zone unit 통과 | 실계정 대기 | server·EventKit·Calendar.app KC-E2 모두 미검증 |
| 시간대/DST 표시 | wall-clock 배치, fall-back overlap, floating/non-Gregorian unit 통과 | 실계정 대기 | KC-E3 |
| 시간대 편집 | preserve-local/instant, floating/zoned, DST gap/overlap 차단 unit 통과 | 서버 통과 / EventKit 대기 | Pacific→Korea update의 UTC 정규화 pass; KaosCal KC-E3 의미 보존은 별도 |
| 반복 occurrence 조회 | occurrence·detached·repeat snapshot과 UI identity unit 통과 | 서버 통과 / EventKit 대기 | finite weekly 5 occurrences pass; 로컬 KC-E4 identity는 별도 |
| 반복 Event Brief 연결 | zoned instant, all-day/floating civil occurrence, detached local anchor unit 통과 | 실계정 대기 | 실제 KC-E4 identifier 변화 필요 |
| 이번 일정·이번 이후 반복 변경 | 명시적 scope·Confirm, basic rule mapping, unsafe 범위 차단 자동 통과 | 서버 부분 통과 / EventKit 대기 | `this_instance` exception pass. `this_and_following`은 connector가 `originalStart`를 제공하지 않아 mutation 전 fail, 재시도 없음 |
| linked future-series reconciliation | 초기 Phase 6의 linked `futureEvents` provider 사전 차단·local 불변 자동 통과 | 자동 통과 / 실계정 negative gate 대기 | 실제 KC-E4에서 write control 차단 확인 필요 |
| local change log·session Undo | additive migration, atomic rebind+log, linked nonrecurring single calendar/time one-shot Undo 자동 통과 | 로컬 구현 통과 / 수동 UI 대기 | 실제 move 한 건의 history/restore 확인; Exchange 지원 증거와 구분 |
| 외부 변경 알림 후 재조회 | 마지막 loaded interval 250ms 병합 재조회 unit 통과 | 실계정 대기 | Calendar.app/Outlook 변경 |
| 외부 삭제 후 local Brief 복구 | 전용 occurrence-aware lookup, 첫 missing·두 번째 명시적 recheck, orphan 보관·exact relink·local-only 삭제 자동 통과 | 로컬 구현 통과 / Exchange 수동 대기 | 일반 범위 fetch 부재·오류·candidate·ambiguous·inconclusive는 삭제 증거가 아님. 실제 Exchange 동기화 지연과 identifier churn은 별도 gate |
| KaosCal linked original delete | saved-link notes/tasks impact, 별도 final Confirm, expected-link CAS, `single`/`this_event`, status+current-link-generation cancellation provenance, no Undo와 partial-success 자동 통과 | 비반복 EventKit·Calendar.app·Outlook 통과 / recurring live 대기 | 전체 189-test gate와 run `20260712-025027-KST`. `single` 원본은 final delete 1회 뒤 외부에서 사라지고 local Brief가 보존됨. recurring series는 서버 생성·cleanup만 통과했고 화면 잠금으로 `thisEvent` mutation은 not tested |
| 권한 철회 후 데이터 제거 | calendar/event/selection 제거 unit 통과 | 실계정 대기 | System Settings 권한 철회 |
| attendee meeting/초대 local-only Brief | `hasAttendees` meeting과 invitation 원본 차단, local notes·task unit flow 통과 | 실계정 대기 | KC-E6와 사용자 주최 meeting에서 변경 메일 없음 확인 필요 |

## 검증 경로 분리

| 경로 | 증명하는 것 | 증명하지 않는 것 |
| --- | --- | --- |
| Outlook connector 서버 QA | 지정 mailbox에서 exact-name calendar 탐색, 서버 측 독립 CRUD·시간대·지원되는 반복 동작, exact fixture cleanup | Exchange Online 판정, macOS TCC, `EKSourceType.exchange`, `allowsContentModifications`, Calendar.app 동기화, KaosCal UI·context·change log·Undo |
| 최신 서명 KaosCal/EventKit QA | 같은 host의 full access, EventKit source·calendar 권한, Calendar.app round-trip, `EKSpan`·identifier churn, 앱 UI와 local context 안전성 | connector만으로 관찰한 서버 상태 자체를 자동으로 보증하지 않음 |

두 경로의 결과는 합쳐 쓰지 않는다. 서버 connector pass는 EventKit pass나 제품의 Exchange 지원 선언을 대체하지 않으며, local calendar가 connector와 같은 mailbox/backend라는 사실도 로컬 확인 전에는 추론하지 않는다.

## 검증 규칙

- 캘린더를 읽으려면 write-only가 아닌 full access가 필요하다.
- 권한 승인 전에 event fetch를 시도했다면 EventKit store를 재설정하고 다시 조회한다.
- 변경 알림은 변경 세부를 제공하지 않으므로 마지막으로 성공한 loaded interval을 다시 fetch한다.
- `Reload events`는 EventKit의 현재 로컬 상태를 다시 읽으며 Exchange 원격 sync를 강제하지 않는다.
- `allowsContentModifications == false`인 경우 원본 일정 변경 UI를 제공하지 않는다.
- attendee가 있는 meeting은 사용자가 organizer여도 v1 원본 변경 UI를 제공하지 않는다.
- 기존 원본 write는 strong identifier로 최신 event를 다시 찾고 지원 필드의 stale snapshot이 같을 때만 실행한다.
- 반복 소속 판정은 `hasRecurrenceRules || isDetached`만 사용한다. 새 비반복 `EKEvent`도 `occurrenceDate == startDate`를 노출할 수 있으므로 `occurrenceDate`는 반복 identity anchor일 뿐이며 비반복 display event에서는 `nil`로 정규화한다.
- 반복 write는 명시적 `이번 일정`/`이번 이후`와 최종 impact Confirm 전에는 실행하지 않는다.
- detached occurrence의 `이번 이후`, complex recurrence의 future/rule 변경, 모든 linked `이번 이후`는 초기 Phase 6에서 write 전에 차단한다. complex recurrence의 `이번 일정` ordinary-field patch는 rule을 그대로 보존해야 한다.
- linked delete는 Phase 7C saved-link impact review와 별도 final Confirm 없이 실행하지 않는다. linked `futureEvents`, attendee/invitation은 계속 차단한다. 실제 Exchange 통과 선언은 run `20260712-025027-KST`의 비반복 `single`에 한정하며 recurring `thisEvent`는 계속 pending이다.
- fake provider와 SQLite 자동 테스트는 Exchange save/remove 통과 증거가 아니다. Calendar.app round-trip을 별도로 기록한다.
- connector의 source create와 destination independent write를 calendar 간 move로 해석하지 않는다. 실제 move API 또는 EventKit/Calendar.app round-trip이 필요하다.
- connector search가 지원되지 않으면 날짜 범위를 제한한 list로 exact run marker만 대조하며, 검색 실패 뒤 mutation을 추측 재시도하지 않는다.
- 네트워크 끊김·동기화 지연은 원본 삭제로 판단하지 않는다.
- 원격 Exchange 이벤트에 KaosCal metadata를 쓰지 않는다.
- Exchange source가 보이더라도 backend를 Exchange Online이라고 추론하지 않는다. 현재 backend는 unknown으로 유지한다.
- raw calendar/event ID, account/email, owner와 source title은 저장소 문서·프로젝트 로그·commit에 복사하지 않는다. connector session의 mutation 응답 식별자는 해당 run의 exact cleanup에만 사용하고 증거에는 run ID, 비식별 상태·개수와 잔여 count만 기록한다.

## 2026-07-11 수동 gate용 빌드 증거 — 화면·Exchange pass 아님

아래는 Phase 5 기준 수동 gate를 열기 위해 준비한 build artifact 증거다. app 실행, 최신 binary에 대한 TCC 상태, `KAOS-TEST` sidebar/source/writable, Calendar.app round-trip을 확인한 기록이 아니며 Phase 6 구현 build도 아니다.

- source commit: `4d19ffa` (`feat: implement phase 5 safe event editing`)
- 환경: macOS 26.4.1, Xcode 26.6 / Build 17F113
- artifact: `/private/tmp/KaosCalPhase5ManualGate/Build/Products/Debug/KaosCal.app` (임시 경로)
- bundle: `com.adtstack.kaoscal`, version `0.1.0`, minimum macOS `14.0`
- ad-hoc CDHash: `61826f59004e96593e76e38bfe571d74f90a1d79`
- signed Debug build: pass
- `codesign --verify --deep --strict`: pass
- entitlements: app sandbox, calendars, Debug `get-task-allow`: pass
- `NSCalendarsFullAccessUsageDescription`: pass
- 화면·실계정 판정: **not run / 수동 대기**

위 CDHash를 Phase 6 실행 증거로 재사용하지 않는다.

## 2026-07-11 Phase 6 build 증거 — 화면·Exchange pass 아님

아래 artifact는 이 문서와 함께 commit되는 Phase 6 checkpoint source tree에서 만들었다. 코드·자동·빌드·서명·앱 bootstrap 증거이며 `KAOS-TEST`의 EventKit source/writable, 최신 창의 권한 상태, Calendar.app/Exchange round-trip 증거는 아니다.

- 환경: macOS 26.4.1, Xcode 26.6 / Build 17F113
- 전체 회귀: **121 tests, 0 failures, 0 unexpected**, `TEST SUCCEEDED`
- result bundle: `/tmp/KaosCalPhase6Root/Logs/Test/Test-KaosCal-2026.07.11_01-17-51-+0900.xcresult`
- unsigned Release: `BUILD SUCCEEDED`, `/private/tmp/KaosCalPhase6Release/Build/Products/Release/KaosCal.app`
- ad-hoc signed Debug: `BUILD SUCCEEDED`, `/private/tmp/KaosCalPhase6Signed/Build/Products/Debug/KaosCal.app`
- bundle/version/minimum: `com.adtstack.kaoscal` / `0.1.0` / macOS `14.0`
- ad-hoc CDHash: `e7d886091b26eab3b00e465c587c5ddbef9f83c2`
- `codesign --verify --deep --strict`: pass
- entitlements: app sandbox, calendars, Debug `get-task-allow`: pass
- `NSCalendarsFullAccessUsageDescription`: pass
- 자동 test 직후 direct/sandbox production DB mtime·size는 각각 `1783678704|110592`, `1783678843|110592`로 test 전과 동일
- signed app 직접 실행 뒤 direct DB는 그대로이고 sandbox DB는 `1783678843|110592`에서 `1783700481|126976`으로 변경. read-only 확인에서 `integrity_check = ok`, foreign-key violation 0건, migration은 `v1_context_store`, `v2_event_change_log`, change log row 0건으로 의도한 additive migration만 적용됨
- Orca computer-use 권한은 accessibility·screenshots 모두 granted였지만 기존 창은 accessibility window를 얻지 못했고 정확한 Phase 6 process에는 별도 window가 잡히지 않았다. screenshot도 만들지 못해 최신 창·TCC·`KAOS-TEST` 화면 판정은 **not verified**
- 실제 calendar fixture write/remove는 수행하지 않음. 사용자의 full-access 허용 보고와 실계정 pass는 계속 분리

## 2026-07-11 Outlook 서버 QA와 로컬 EventKit gate 분리

- run: `20260711-1512-7C4E`
- mailbox time zone: `Korea Standard Time`
- calendar preflight: `KAOS-TEST`(source)와 `일정`(destination)이 각각 exact-name 1개, editable, distinct, same owner. owner·account·calendar identifier와 source title은 영속 증거에 복사하지 않음
- source nonrecurring fixture: create → fetch → update **pass**
- destination fixture: source와 별도의 independent write **pass**. 이는 calendar move가 아님
- time-zone fixture: Pacific zone으로 만든 뒤 Korea zone으로 update했을 때 UTC normalization **pass**
- recurrence fixture: 종료가 있는 weekly series에서 occurrence 5개 확인 **pass**
- recurrence exception: `this_instance` **pass**
- recurrence split: `this_and_following`은 connector가 필수 `originalStart`를 제공하지 않아 mutation 전에 **fail**. 부분 mutation은 없었고 재시도하지 않음
- calendar 간 move: connector에 move API가 없어 **not tested**
- all-day: create schema에 `isAllDay`가 없어 **not tested**
- event search: connector가 MSA mailbox에서 지원하지 않아 mutation 없이 bounded list fallback으로 exact marker를 확인함. 이 제한 때문에 backend를 Exchange Online이라고 판정하지 않음
- cleanup: run에서 생성한 exact 네 fixture만 응답 식별자로 삭제 **pass**. 두 차례 즉시 확인과 최종 지연 재확인을 포함한 세 번의 bounded residue 확인 모두 source/destination `0/0`
- local EventKit: 최신 서명 host authorization은 `notDetermined`; 권한 prompt UI를 사용할 수 없어 요청 run을 중단했고 local fixture write는 0회. TCC full access, `.exchange` source, `allowsContentModifications`, Calendar.app round-trip은 **blocked / pending**
- 판정: 서버 측 제한된 CRUD·time-zone·recurrence·cleanup은 통과했다. 실제 cross-calendar move, all-day, `this_and_following`, local EventKit/Calendar.app은 통과로 표시하지 않으며 Exchange 지원 완료를 선언하지 않는다.

## 2026-07-11 signed FinalRelease EventKit 비반복 CRUD gate

- run: `20260711-1626-B7D2`
- host: ad-hoc signed Release, CDHash `63ded03a9d704976c4ba45340f2748eda9892382`; `codesign --verify --deep --strict` **pass**
- 권한·calendar preflight: `Full calendar access` 확인. sidebar에서 `KAOS-TEST`와 `일정`이 모두 `Exchange`이며 lock 없이 writable로 표시됨
- create: `KAOS-TEST`에 attendee·recurrence 없는 고유 marker fixture를 KaosCal UI로 생성 **pass**
- server observation: 한 개의 `singleInstance`, recurrence null, 입력한 현지 시각에 대응하는 UTC 정규화 확인 **pass**
- restart/refetch: 앱을 종료·재실행해 fixture를 다시 조회했을 때 반복 badge와 recurrence scope 선택 없이 비반복 일정으로 표시 **pass**
- update: 동일 fixture의 지원 필드를 한 번 수정 **pass**. 서버에서도 단일 instance와 recurrence null 유지
- delete: recurrence scope 없이 single delete **pass**
- cleanup: 최종 marker 잔여 source/destination `0/0`
- 발견·수정한 회귀: 새 비반복 `EKEvent`에서도 EventKit이 `occurrenceDate == startDate`를 노출할 수 있어 이를 반복 소속으로 해석하면 잘못된 반복 badge·scope가 나타났다. 반복 소속은 `hasRecurrenceRules || isDetached`로 한정하고 `occurrenceDate`는 반복 identity anchor로만 사용하며 single에서는 `nil`로 정규화했다.
- 자동 회귀: **124 tests, 1 intentional skip, 0 failures**
- 데이터 안전 gate: full test와 live QA 전후 direct/sandbox production DB 및 각각의 `-wal`·`-shm` 상태가 모두 불변
- 이번 run에서 통과로 표시하지 않는 항목: Calendar.app visual round-trip, all-day, time-zone 변경, 실제 recurrence occurrence·`이번 이후` split, `KAOS-TEST`→`일정` move. 기존 서버 run의 recurrence/time-zone 결과는 이 local run의 대체 증거로 합치지 않음
- 판정: signed FinalRelease의 full access, 두 Exchange calendar의 writable 표시, `KAOS-TEST` 비반복 create→restart/refetch→single update→single delete와 exact cleanup은 **pass**. 위 미실행 항목과 backend의 Exchange Online 판정은 계속 pending이다.

## 2026-07-11 legacy Brief compatibility 후속 checkpoint

- live run `20260711-1626-B7D2` 뒤 최종 코드 검토에서, 오분류 build가 만든 single Event Brief link가 recurring identity로 남아 수정 mapper의 `single:v1`과 강한 ID 단계에서도 불일치할 수 있음을 확인했다.
- runtime 호환 경로는 현재 single과 legacy link가 강한 identifier 및 calendar/title/location/time/local-components/fingerprint/series/occurrence anchor까지 모두 정확히 같을 때만 기존 context를 연결하고 `single:v1`로 snapshot을 정상화한다. notes/tasks는 유지한다.
- navigation은 read-only다. legacy 구조와 strong identifier가 맞지만 snapshot이 다르면 confirmation-required candidate로만 노출하고, identifier가 없으면 기존 exact/fingerprint candidate 정책을 유지해 다른 recurrence occurrence를 자동 연결하지 않는다.
- 이 Mac의 direct/sandbox production DB는 검토 시 `event_links` 0행이었지만, 업그레이드 안전성은 별도 회귀로 보강했다.
- 자동 gate: **132 tests, 1 intentional skip, 0 failures, 0 unexpected**. 테스트 전후 두 production DB와 WAL/SHM 상태는 완전히 동일했다.
- 최종 build-only artifact: `/private/tmp/KaosCalFinalReleaseCompat/Build/Products/Release/KaosCal.app`, CDHash `511a11258d95a49c826b49dc463a79039707807e`. strict codesign, hardened runtime, sandbox, Calendar entitlement, usage description 통과; get-task-allow와 XCTest plug-in/link 없음.
- 이 후속 artifact에는 새 Exchange fixture write를 실행하지 않았다. 따라서 실계정 CRUD pass는 직전 live artifact에, legacy normalization과 최종 서명/build pass는 이 artifact에 각각 귀속한다. 남은 Calendar.app, all-day, time-zone 변경, recurrence/future split, calendar move 판정은 그대로 pending이다.

## 2026-07-11 Phase 7A lifecycle 후속 checkpoint

- active occurrence의 유효 종료를 기준으로 `scheduled ↔ completed`를 파생하고, 완료 일정의 미완료 After task만 Today/Upcoming과 전용 `After Review`에 투영한다. 이 동작은 local Context DB에만 쓰며 EventKit 원본을 수정하지 않는다.
- zoned instant, all-day exclusive end, floating civil components와 반복 occurrence별 독립 상태를 자동 검증했다. cancelled/orphaned context와 non-active link는 시간 reconciliation이 덮어쓰지 않는다.
- 반복 write 후 identifier를 공유하는 다른 occurrence를 선택할 수 있던 focus 경로는 exact display ID 우선, 동일 calendar와 occurrence anchor를 요구하는 fallback으로 좁혔다.
- 자동 gate: **145 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 결과 bundle은 `/private/tmp/KaosCalPhase7AFull.xcresult`다.
- 당시 Phase 7A build-only artifact: `/private/tmp/KaosCalPhase7ARelease/Build/Products/Release/KaosCal.app`, CDHash `abfb685b03f1ff919f83a955e5b819e3c6b57df6`. strict codesign, hardened runtime, sandbox, Calendar entitlement, usage description 통과; get-task-allow와 XCTest plug-in/link 없음.
- exact Release는 EventKit write 없이 1360×840 onscreen 창을 생성했고 종료 뒤 프로세스가 남지 않았다. 테스트와 bootstrap 전후 direct/sandbox production DB의 mtime·size·SHA-256 및 WAL/SHM 부재는 동일했다.
- 이 checkpoint는 Exchange fixture를 새로 만들지 않았으므로 실제 비반복 CRUD 증거는 run `20260711-1626-B7D2`에 계속 귀속한다. Calendar.app, all-day, time-zone 변경, recurrence/future split, calendar move 판정은 그대로 pending이다.

## 2026-07-11 Sidebar mini month 후속 checkpoint

- mini month는 EventKit mutation을 만들지 않는 local navigation UI다. 월 화살표는 local browse state만 바꾸고 날짜 선택만 기존 visible-period fetch 경계로 보낸다.
- 자동 gate: **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 검토 수정 뒤 최종 결과 bundle은 `/private/tmp/KaosCalMiniMonthPostReview.xcresult`다.
- 당시 post-review mini-month build-only artifact: `/private/tmp/KaosCalMiniMonthRelease/Build/Products/Release/KaosCal.app`, CDHash `92e16853c099db014b3f3f2d370d0b57ba44bc90`. strict codesign, hardened runtime, sandbox, Calendar entitlement, usage description 통과; get-task-allow와 XCTest plug-in/link 없음.
- exact Release가 1482×931 onscreen 창을 만들고 정상 종료 뒤 process 0임을 확인했다. 전체 test와 bootstrap 전후 direct/sandbox production DB의 mtime·size·SHA-256 및 WAL/SHM 부재는 동일했다.
- 새 Exchange fixture write를 실행하지 않았다. 실제 비반복 CRUD 증거는 계속 run `20260711-1626-B7D2`에 귀속하며 Calendar.app, all-day, time-zone 변경, recurrence/future split, calendar move 판정은 pending이다.

## 2026-07-11~12 AppIcon 최초 opaque build와 compatibility correction

- `AppIcon.appiconset` 10개 macOS slot을 추가하고 Xcode가 `AppIcon.icns`, `CFBundleIconFile`과 `CFBundleIconName`을 생성하는 것을 확인했다.
- 최초 opaque build-only artifact: `/private/tmp/KaosCalIconRelease/Build/Products/Release/KaosCal.app`, CDHash `d8990eec4462f6662f5cb7676cf844c35f2b8a98`. strict codesign, hardened runtime, sandbox, Calendar entitlement 통과.
- 최초 opaque AppIcon build 당시 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**를 통과했다. 당시 결과 bundle은 `/private/tmp/KaosCalAppIconFinal.xcresult`다.
- exact Release가 1482×931 onscreen 창을 만들고 종료 뒤 process 0임을 확인했다. NSWorkspace가 icon을 valid로 읽고 여러 logical 표현을 반환했으며, source catalog는 최대 1024px과 1x/2x slot을 제공한다. 테스트와 bootstrap 전후 production DB는 불변이다.
- 이 checkpoint도 EventKit/Exchange write를 실행하지 않았다. live 비반복 CRUD 증거와 남은 Calendar.app/all-day/time-zone/recurrence/move 판정은 이전 run과 분리한다.
- 후속 호환 검토에서 macOS 14/15 legacy `.icns`가 최신 system mask를 보장하지 않아 opaque square가 각지게 보일 수 있음을 확인했다. 이 artifact는 release candidate에서 제외했다.
- 현재 worktree는 동일 표식의 full-bleed squircle과 transparent corner를 가진 alpha PNG 10개 slot로 교체했다. corner alpha 0, center alpha 255와 16/64/128/1024px 시각 상태를 확인했다.
- 사용자 확장 권한 승인 뒤 transparent fallback을 새 경로에서 재빌드했다. 최종 artifact는 `/private/tmp/KaosCalIconCompatRelease/Build/Products/Release/KaosCal.app`, CDHash `bc2ddd83c9d7f5e1bfd62241b0e02e63b23308b6`이며 strict codesign, hardened runtime, sandbox, Calendar entitlement를 통과했다.
- `AppIcon.icns`를 iconset으로 역추출해 16/32/128/256px 표현의 alpha, 네 corner 0과 center 255를 확인했다. Info.plist의 `CFBundleIconFile/Name = AppIcon`, Assets.car, XCTest 비포함도 확인했다.
- 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. 최종 result bundle은 `/private/tmp/KaosCalAppIconCompatFinal.xcresult`다.
- exact Release가 1512×949 onscreen 창을 만들고 정상 종료 뒤 process 0임을 확인했다. test와 bootstrap 전후 production DB mtime·size·SHA-256 및 WAL/SHM 부재는 동일했다. 이 final gate도 EventKit/Exchange write를 실행하지 않았다.

## 2026-07-12 Phase 7B 외부 삭제 복구 자동·Release checkpoint

- 일반 Day/Week/Agenda 구간 fetch에서 일정이 보이지 않는 사실은 삭제 증거로 사용하지 않는다. 저장된 calendar/item/event/external identifier와 occurrence anchor를 사용하는 별도 lookup만 복구 상태를 바꿀 수 있다.
- 첫 명시적 `notFound`는 link를 `missing`으로만 만들고 local notes/tasks와 context lifecycle을 보존한다. 사용자가 `Check Again`을 눌러 두 번째 전용 lookup도 `notFound`일 때만 orphan review를 연다.
- 권한·provider 오류, weak/ambiguous candidate와 recurring occurrence를 확정할 수 없는 `inconclusive`는 miss로 세지 않는다. 멀리 이동한 detached occurrence나 series seed의 제한 때문에 false orphan이 되지 않도록 보수적으로 남긴다.
- provider의 명시적 cancelled evidence는 local context를 cancelled로 표시한다. 이후 같은 occurrence의 fresh exact found는 새 positive evidence로 scheduled/completed lifecycle을 다시 계산한다.
- 명시적 relink는 선택 후보를 provider에서 마지막으로 exact 검증하고 expected-link 전체 상태를 CAS로 확인한 뒤 context/link/relinked log를 한 SQLite transaction에서 갱신한다. original EventKit notes는 v1 link에 저장되지 않았으므로 relink 전 change snapshot의 `originalNotes`는 unavailable(`nil`)이며 local Brief notes로 대체하지 않는다.
- `Delete local Brief`는 local FK cascade만 수행하고 EventKit create/update/delete를 호출하지 않는다. 이 Phase 7B checkpoint 당시 KaosCal에서 linked 원본을 지우는 기능은 Phase 7C까지 잠겨 있었다.
- 최종 전체 **175 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**. Debug result bundle은 `/private/tmp/KaosCalPhase7BFinal-20260712-0155.xcresult`다.
- build-only Release `/private/tmp/KaosCalPhase7BFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `f3b30718434641dbbd2dbec90f82581342d47506`은 strict codesign, hardened runtime, sandbox, Calendar entitlement, usage description을 통과했고 get-task-allow·XCTest를 포함하지 않는다.
- exact artifact는 1482×931 onscreen 창을 만들고 정상 종료 뒤 process 0이었다. test와 bootstrap 전후 direct/sandbox production DB mtime·size·SHA-256과 WAL/SHM 부재가 동일했고 integrity/FK 및 v1/v2 migration 목록도 정상이다.
- 어느 calendar에서든 strong identifier seed의 recurrence/occurrence가 맞지 않으면 inconclusive다. 살아 있는 series의 one-off deletion과 bounded search 밖 detached move는 구분할 수 없어 automatic orphan을 주장하지 않고 manual exact relink로 남긴다.
- 이 checkpoint에서는 Exchange/EventKit fixture write나 외부 삭제를 실행하지 않았다. 실제 Exchange 동기화 지연, Calendar.app 외부 삭제와 identifier churn은 수동 gate이며 기존 live CRUD run `20260711-1626-B7D2`를 대체하지 않는다.

## 2026-07-12 Phase 7C linked original delete 자동 checkpoint

- active linked Brief의 notes 글자 수, section별 task 수·제목, 최근 history, expected `EventLink`와 saved-link `EventChangeSnapshot`을 read-only로 준비한다. first alert와 Back/Cancel에는 EventKit/SQLite write가 없다.
- 별도 final Confirm 직전에 현재 mutation context와 full expected-link/snapshot을 다시 검증하고, provider 성공 뒤 local finalize transaction에서도 같은 CAS를 반복한다.
- nonrecurring은 `single`, recurring occurrence는 `this_event`만 지원한다. linked `futureEvents`, attendee meeting/invitation과 read-only 원본은 provider 호출 전에 차단한다.
- successful delete receipt 뒤 context lifecycle `cancelled`, link status `orphaned`, previous available Undo supersede와 unavailable `cancelled` log를 한 SQLite transaction으로 저장한다. context ID, local notes/tasks, saved link와 `last_seen_at`은 유지한다. deleted-original 표시는 상태쌍만 보지 않고 이 cancellation provenance가 현재 link 세대에 남아 있는지도 확인한다.
- deletion log before/after는 같은 saved-link snapshot이고 v1에 없는 originalNotes는 nil/unavailable이다. local notes를 대신 넣지 않으며 새 log와 process session 모두 Undo를 제공하지 않는다.
- receipt 모순, final CAS/log 실패나 EventKit-local 사이 crash는 원본을 자동 재생성하지 않는 no-retry 부분 성공이다. 실패한 local transaction은 전체 rollback되고 false log 없이 Brief/notes/tasks가 남아 Task Center recovery로 이어진다.
- 이후 `relinked` log가 cancellation보다 `(created_at, rowid)` 순서상 늦으면 과거 deletion provenance를 무효화한다. 같은 timestamp에서는 더 큰 rowid가 최신이며, 이후 외부 cancellation으로 다시 `cancelled + orphaned`가 되어도 새 KaosCal deletion log 없이는 deleted-original로 표시하지 않는다.
- Phase 7C 신규 회귀 총 14개를 포함한 전체 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**. result bundle은 `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`다.
- build-only Release `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6b1da198f969cb033946fdb72b2b2e46392310f2`는 strict codesign, hardened runtime, sandbox, Calendar entitlement와 usage description을 통과했고 get-task-allow·XCTest plug-in/link가 없다.
- exact binary는 `XCTestConfigurationFilePath=Phase7CReleaseSmoke`로 production DB open을 차단한 채 5초 이상 실행된 뒤 종료했고 process 0이었다. 전후 direct/sandbox production DB는 각각 `1783704658|126976`, `1783700481|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 WAL/SHM 부재가 불변이었다. 두 DB의 integrity `ok`, FK violation 0, migration `v1_context_store`·`v2_event_change_log`도 유지된다. computer-use runtime 부재로 onscreen 시각 증거는 이번 gate에 포함하지 않았다.
- 위 결과는 그 자동 checkpoint 시점의 fake provider/local DB 증거다. 당시 실제 EventKit/Exchange 삭제 write, Calendar.app/Outlook round-trip, recurring deletion exception과 process crash recovery는 실행하지 않았으며 기존 live run `20260711-1626-B7D2`의 unlinked 비반복 CRUD 증거로 대체하지 않았다. 이후 비반복 live 결과는 아래 별도 run에 귀속한다.
- 기존 v1 `cancelled`/`orphaned`와 v2 `cancelled`/scope/unavailable Undo를 재사용했으므로 schema migration은 없다.

## 2026-07-12 Phase 7C linked original delete live Exchange gate

- run: `20260712-025027-KST`; Asia/Seoul
- exact host: `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6b1da198f969cb033946fdb72b2b2e46392310f2`
- 권한·calendar preflight: `Full calendar access`; `KAOS-TEST`와 `일정`이 각각 exact-name `Exchange` calendar이며 lock 없이 writable
- nonrecurring fixture: `KAOSCAL-P7C-LIVE-20260712-025027-KST-SINGLE`, 2026-07-12 15:00–16:00 KST, attendee 없음, recurrence 없음
- local preparation: Notes 1건과 Before/During/After task 각 1건을 저장했고 앱 종료·재실행 뒤에도 Notes와 총 3개 task가 유지됐다. 본문과 task text는 영속 증거에 기록하지 않았다.
- review·Back: 첫 alert와 final review가 `Scope: Single event`, local Notes와 section별 task 수를 표시했다. Back 경로에는 provider/local write가 없었고 Outlook exact-marker count는 계속 1이었다.
- final delete: `Delete Original & Keep Brief`를 정확히 1회 실행했다. Task Center는 `Original deleted · Local Brief kept`, 총 3개 task와 Notes를 표시했고 Undo를 제공하지 않았으며 Relink와 Delete Local Brief 진입점을 유지했다.
- 외부 관찰: Outlook exact-marker count는 즉시 확인과 지연 확인에서 모두 0이었고 Calendar.app의 exact title 검색은 `결과 없음`이었다. Outlook과 Calendar.app 결과는 KaosCal UI/local DB 증거와 분리해 기록했다.
- sandbox DB read-only 검증: `query_only` 연결에서 `integrity_check`, foreign key와 v1/v2 migration이 모두 정상이다. 대상 context/link는 1/1로 보존되고 `cancelled`/`orphaned`, Notes 존재, task 3개와 section별 1개를 확인했다. `cancelled`/`single`/`unavailable` log는 정확히 1개, available Undo는 0개이며 before/after payload와 current-link-generation deletion provenance가 유효했다. 보존 대상 combined hash는 전후 동일했지만 실제 hash 값은 기록하지 않았다.
- 자동 증거는 변경되지 않았다. Phase 7C 신규 회귀 14개를 포함한 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**와 `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`를 계속 사용한다.
- recurring fixture: `KAOSCAL-P7C-LIVE-20260712-025027-KST-RECUR`는 attendee 없는 daily series로 서버에서 `seriesMaster`와 2026-07-12~14 occurrence 3개가 확인됐다. UI 진입 전에 macOS session이 자동 잠겨 `thisEvent` live mutation은 **not tested**다. 제품 failure로 판정하지 않으며 automated recurrence tests의 pass도 변경하지 않는다.
- cleanup: recurring exact series 전체를 Outlook에서 삭제했고 최종 서버 residue는 single 0, recurring 0이다. nonrecurring 원본도 외부 residue 0이다. single local Brief는 증거로 의도적으로 남겨 두었고 화면 잠금으로 UI-only cleanup을 완료하지 못했다. 다음 수동 세션에서 `Delete Local Brief`로 정리하고 원본 비재생성을 확인해야 한다.
- 비밀정보 경계: raw calendar/event identifier, account/email, Notes·task 본문과 실제 combined hash는 문서에 기록하지 않았다.
- 판정: Phase 7C nonrecurring linked original delete의 exact Release→EventKit→Calendar.app/Outlook→local provenance 경로는 **pass**. recurring `thisEvent` mutation과 retained single local Brief cleanup은 **blocked by session lock / manual pending**이며 backend 종류와 process crash recovery도 계속 미판정이다.

## 2026-07-12 Phase 8 Multi-Calendar Clarity checkpoint

- 관련 범위: local role, role별 virtual Set, source/account/permission presentation, typed read-only reason, 비파괴 duplicate candidate. 이 단계는 Exchange calendar/event 이름·색·권한이나 원본 event를 쓰지 않는다.
- 역할은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`다. subscribed/birthdays만 현재 EventKit source에서 Subscription으로 추론하고, 사용자가 고른 explicit role만 `v3_calendar_clarity.calendar_preferences`에 sparse 저장한다. source와 override가 모두 없으면 account type을 추측하지 않고 Other다.
- Set은 All과 역할별 runtime filter이며 Day/Week/Agenda visibility만 좁힌다. raw EventKit fetch, Event Brief observation, Task Center, relink와 writable destination은 필터링하지 않는다.
- read-only reason은 invitation→attendee→subscription→birthdays→provider-reported read-only 순서이며 UI와 AppState write preflight가 같은 typed projection을 사용한다. 공유 Exchange의 Owner/Editor/Viewer ACL 원인은 EventKit이 제공하지 않으므로 추측하지 않는다.
- duplicate는 다른 calendar의 normalized title과 timed start/end 각 15분 이내 또는 같은 all-day civil range를 검토 후보로 만든다. strong same occurrence를 제외하고 자동 merge·hide·delete·EventKit write는 없다. fetch마다 index를 한 번 계산한다.
- 자동 검증: **199 tests executed, 198 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**. result bundle `/private/tmp/KaosCalPhase8FinalTests-20260712-1415.xcresult`.
- Release: `/private/tmp/KaosCalPhase8FinalRelease/Build/Products/Release/KaosCal.app`; CDHash `6c595445dadfb60588410329222557d00865c222`. strict codesign, hardened runtime, sandbox·Calendar entitlement와 full-access usage description을 통과했고 get-task-allow·XCTest를 포함하지 않는다.
- DB gate: test 전후 direct/sandbox production DB는 불변이었다. exact Release 정상 bootstrap 전 sandbox v2 DB를 `/private/tmp/KaosCalPhase8MigrationPreflight-20260712-1406/kaoscal-pre-v3.sqlite`로 복사하고 v3를 적용했다. 이후 integrity `ok`, FK violation 0, `calendar_preferences` 0행, 기존 context/link/task/personal/change-log count·SHA3 불변과 WAL/SHM 부재, process 0을 확인했다.
- 증거 경계: 정상 bootstrap은 기존 EventKit 일정을 읽었지만 Phase 8 write를 실행하지 않았고 새 role row도 만들지 않았다. session이 잠겨 Sidebar·Inspector·고밀도 card·VoiceOver 실화면은 확인하지 못했다. Viewer calendar도 없어 shared read-only reason은 **live blocked**다. 이 결과만으로 backend를 Exchange Online이라고 판정하지 않는다.

## 테스트 기록 형식

각 실행 후 아래 내용을 [implementation-log.md](implementation-log.md)에 남긴다.

```text
검증 경로: Outlook connector server / signed KaosCal EventKit
run ID:
환경: macOS / Xcode / backend unknown 여부
테스트 데이터: KC-Ex
절차:
기대 결과:
실제 결과:
EventKit 오류 또는 관찰:
cleanup 및 source/destination 잔여 count:
판정: pass / fail / blocked
```

## 근거

- [Apple: Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Apple: Updating with notifications](https://developer.apple.com/documentation/eventkit/updating-with-notifications)
- [Apple: EKCalendar.allowsContentModifications](https://developer.apple.com/documentation/eventkit/ekcalendar/allowscontentmodifications)
