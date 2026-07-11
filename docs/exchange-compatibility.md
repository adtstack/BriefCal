# Exchange Compatibility

> 상태: Phase 6 recurrence·safe-move·change-log·session Undo 자동·Release·ad-hoc 서명 checkpoint / Outlook 서버 측 부분 통과·로컬 EventKit TCC gate 대기
> 제품 대상: macOS Calendar에 구성된 Exchange Online
> 현재 테스트 환경: backend 종류 미확인. Outlook connector run `20260711-1512-7C4E`에서 `KAOS-TEST`(source)·`일정`(destination)이 각각 exact-name 1개, editable, distinct, same owner로 관찰됐지만 connector의 MSA 제한 때문에 Exchange Online 또는 로컬 EventKit `.exchange` source라고 판정하지 않는다. 최신 서명 EventKit host는 authorization `notDetermined`이고 권한 UI를 사용할 수 없어 local write 0회로 중단
> 마지막 갱신: 2026-07-11

## 지원 선언 기준

KaosCal은 추측으로 Exchange 기능을 지원한다고 선언하지 않는다. 아래 매트릭스에서 실제 macOS·Exchange 조합으로 통과한 항목만 베타 지원 범위에 넣는다.

| 기능 | 현재 테스트 환경 | 상태 | 증거 |
| --- | --- | --- | --- |
| full calendar access | 사용자는 허용을 보고했지만 최신 서명 host는 `notDetermined` | 로컬 blocked / 수동 대기 | 권한 prompt 승인 뒤 동일 host의 `Full calendar access`, EventKit fetch와 재실행 유지 증거 필요; local write 0회 |
| Exchange source·calendar 식별 | 서버 connector에서 두 exact-name calendar를 구분 | 서버 확인 / EventKit 대기 | `KAOS-TEST`·`일정` 각각 1개·distinct·same owner. 로컬 `.exchange`, sidebar/color는 별도 확인 필요 |
| editable calendar 확인 | 서버 connector에서 두 calendar 모두 editable | 서버 확인 / EventKit 대기 | 실제 EventKit 노출과 `allowsContentModifications` 확인 필요 |
| read-only 구분 | `allowsContentModifications` mapping·unit state 구현 | blocked | Viewer calendar 미준비, Phase 8 전 해소 |
| 시간 일정 조회 | 서버 fixture create/fetch와 bounded list 확인 | 서버 통과 / EventKit 대기 | source create-fetch-update pass; local KC-E1 표시 필요 |
| 비반복 일정 생성 | writable/default calendar 선택·draft validation·receipt focus unit 통과 | 서버 통과 / EventKit 대기 | source create pass, destination independent write pass; KaosCal·Calendar.app 확인 필요 |
| 비반복 일정 수정 | strong re-fetch, fresh snapshot, changed-field patch, linked rebind unit 통과 | 서버 통과 / EventKit 대기 | source fetch-update pass; KaosCal KC-E1 round-trip 필요 |
| 비반복 일정 삭제 | local Brief 없는 일정만 remove하도록 AppState unit 통과 | 서버 cleanup 통과 / EventKit 대기 | 생성한 네 fixture exact cleanup과 잔여 0/0 확인; KaosCal remove는 별도 |
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
- 반복 write는 명시적 `이번 일정`/`이번 이후`와 최종 impact Confirm 전에는 실행하지 않는다.
- detached occurrence의 `이번 이후`, complex recurrence의 future/rule 변경, 모든 linked `이번 이후`는 초기 Phase 6에서 write 전에 차단한다. complex recurrence의 `이번 일정` ordinary-field patch는 rule을 그대로 보존해야 한다.
- linked delete는 Phase 7 orphan review 전까지 실행하지 않는다.
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
