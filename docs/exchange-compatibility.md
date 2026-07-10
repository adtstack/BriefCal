# Exchange Compatibility

> 상태: Phase 6 recurrence·safe-move·change-log·session Undo 자동·Release·ad-hoc 서명 checkpoint / 실계정 EventKit 검증 대기
> 제품 대상: macOS Calendar에 구성된 Exchange Online
> 현재 테스트 환경: Exchange backend 종류 미확인. 사용자는 `KAOS-TEST`를 수정 가능 대상으로 지정했고 2026-07-11 macOS 전체 캘린더 접근을 허용했다고 보고했지만, 최신 서명 앱의 실제 권한·source·writable 표시는 독립 확인 대기
> 마지막 갱신: 2026-07-11

## 지원 선언 기준

KaosCal은 추측으로 Exchange 기능을 지원한다고 선언하지 않는다. 아래 매트릭스에서 실제 macOS·Exchange 조합으로 통과한 항목만 베타 지원 범위에 넣는다.

| 기능 | 현재 테스트 환경 | 상태 | 증거 |
| --- | --- | --- | --- |
| full calendar access | 사용자가 2026-07-11 허용했다고 보고 | 사용자 보고 / 수동 확인 대기 | 최신 서명 앱의 `Full calendar access`, EventKit fetch와 재실행 유지 화면 증거 필요 |
| Exchange source·calendar 식별 | `EKSourceType.exchange`·calendar color mapping 구현, 실계정 미확인 | 수동 대기 | `KAOS-TEST` sidebar/color 확인 필요 |
| editable calendar 확인 | 사용자가 `KAOS-TEST`를 수정 가능 테스트 대상으로 지정 | 수동 대기 | 실제 EventKit 노출과 `allowsContentModifications` 확인 필요 |
| read-only 구분 | `allowsContentModifications` mapping·unit state 구현 | blocked | Viewer calendar 미준비, Phase 8 전 해소 |
| 시간 일정 조회 | 미검증 | 대기 | KC-E1 |
| 비반복 일정 생성 | writable/default calendar 선택·draft validation·receipt focus unit 통과 | 실계정 대기 | `KAOS-TEST` 생성 후 Calendar.app 확인 필요 |
| 비반복 일정 수정 | strong re-fetch, fresh snapshot, changed-field patch, linked rebind unit 통과 | 실계정 대기 | KC-E1 제목·시간·장소·원본 notes round-trip 필요 |
| 비반복 일정 삭제 | local Brief 없는 일정만 remove하도록 AppState unit 통과 | 실계정 대기 | `KAOS-TEST` 전용 fixture 삭제와 Calendar.app 확인 필요 |
| calendar 간 이동 | local Brief 없는 move와 linked safe move·impact Confirm·context rebind 자동 통과 | 실계정 대기 | `KAOS-TEST-DEST`, context 유지, identifier churn 관찰 필요 |
| 종일·다일 일정 조회 | 자정/`23:59:59` raw end 정규화, 배타 범위·all-day span unit 통과 | 실계정 대기 | KC-E2 |
| 종일 일정 생성·편집 | 포함 종료↔배타 종료, 자정 변환, reference time zone unit 통과 | 실계정 대기 | KC-E2 Calendar.app round-trip 필요 |
| 시간대/DST 표시 | wall-clock 배치, fall-back overlap, floating/non-Gregorian unit 통과 | 실계정 대기 | KC-E3 |
| 시간대 편집 | preserve-local/instant, floating/zoned, DST gap/overlap 차단 unit 통과 | 실계정 대기 | KC-E3 Calendar.app·Exchange 서버 정규화 확인 필요 |
| 반복 occurrence 조회 | occurrence·detached·repeat snapshot과 UI identity unit 통과 | 실계정 대기 | KC-E4 |
| 반복 Event Brief 연결 | zoned instant, all-day/floating civil occurrence, detached local anchor unit 통과 | 실계정 대기 | 실제 KC-E4 identifier 변화 필요 |
| 이번 일정·이번 이후 반복 변경 | 명시적 scope·Confirm, basic rule mapping, unsafe 범위 차단 자동 통과 | 실계정 대기 | KC-E4 thisEvent/futureEvents, detach/series split 관찰 필요 |
| linked future-series reconciliation | 초기 Phase 6의 linked `futureEvents` provider 사전 차단·local 불변 자동 통과 | 자동 통과 / 실계정 negative gate 대기 | 실제 KC-E4에서 write control 차단 확인 필요 |
| local change log·session Undo | additive migration, atomic rebind+log, linked nonrecurring single calendar/time one-shot Undo 자동 통과 | 로컬 구현 통과 / 수동 UI 대기 | 실제 move 한 건의 history/restore 확인; Exchange 지원 증거와 구분 |
| 외부 변경 알림 후 재조회 | 마지막 loaded interval 250ms 병합 재조회 unit 통과 | 실계정 대기 | Calendar.app/Outlook 변경 |
| 권한 철회 후 데이터 제거 | calendar/event/selection 제거 unit 통과 | 실계정 대기 | System Settings 권한 철회 |
| attendee meeting/초대 local-only Brief | `hasAttendees` meeting과 invitation 원본 차단, local notes·task unit flow 통과 | 실계정 대기 | KC-E6와 사용자 주최 meeting에서 변경 메일 없음 확인 필요 |

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
- 네트워크 끊김·동기화 지연은 원본 삭제로 판단하지 않는다.
- 원격 Exchange 이벤트에 KaosCal metadata를 쓰지 않는다.
- Exchange source가 보이더라도 backend를 Exchange Online이라고 추론하지 않는다. 현재 backend는 unknown으로 유지한다.

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

## 테스트 기록 형식

각 실행 후 아래 내용을 [implementation-log.md](implementation-log.md)에 남긴다.

```text
환경: macOS / Xcode / Exchange 종류
테스트 데이터: KC-Ex
절차:
기대 결과:
실제 결과:
EventKit 오류 또는 관찰:
판정: pass / fail / blocked
```

## 근거

- [Apple: Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Apple: Updating with notifications](https://developer.apple.com/documentation/eventkit/updating-with-notifications)
- [Apple: EKCalendar.allowsContentModifications](https://developer.apple.com/documentation/eventkit/ekcalendar/allowscontentmodifications)
