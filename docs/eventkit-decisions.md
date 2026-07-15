# EventKit Decisions

## 목적

KaosCal v1은 직접 sync engine을 만들지 않고 EventKit을 통해 macOS Calendar와 연결한다.
이 문서는 EventKit 사용에서 제품 품질과 데이터 안전성에 영향을 주는 결정을 고정한다.

최신 범위와 대체 이력은 [ADR](adr/README.md)을 우선한다.

## 결정 1: EventKit은 원본 일정의 유일한 v1 입출력 계층이다

v1에서는 Google Calendar API, Microsoft Graph, CalDAV, iCloud API를 직접 구현하지 않는다.
사용자는 macOS System Settings와 Calendar.app에 이미 연결된 계정을 통해 일정을 사용한다.

Exchange 우선 지원 범위는 macOS Calendar에 구성된 Exchange Online calendar다. 온프레미스 Exchange는 실제 호환성 검증 전까지 지원을 약속하지 않는다.

이유:
- v1의 차별점은 sync coverage가 아니라 Event Brief다.
- 직접 sync를 만들면 인증, conflict, recurrence, rate limit, offline queue가 제품의 중심을 밀어낸다.
- macOS-first 제품답게 시스템 계정과 권한 모델을 활용한다.

## 결정 2: KaosCal 고유 데이터는 EventKit에 저장하지 않는다

EventKit 이벤트에는 원본 일정 데이터만 저장한다.
Before/During/After 체크리스트, KaosCal notes, Event Brief 상태는 SQLite에 저장한다. change log는 Phase 6, 명시적 calendar role preference는 Phase 8에서 같은 로컬 저장소에 additive migration으로 추가했다.

금지:
- 체크리스트를 `EKEvent.notes`에 serialize
- KaosCal metadata를 description 문자열에 숨겨 저장
- EventKit URL field를 local context id 저장소로 오용

허용:
- 사용자가 직접 입력한 원본 event notes는 EventKit notes로 저장
- KaosCal 전용 notes는 local DB로 저장

## 결정 3: 권한 상태는 UI 상태로 명시한다

권한은 단순 예외가 아니라 주요 앱 상태다.

필수 상태:
- not determined
- authorized/full access
- denied
- restricted
- write-only 또는 제한된 접근 상태가 있는 OS 버전
- unknown future status

macOS 14 이상에서 KaosCal은 `requestFullAccessToEvents`를 사용한다. 일정 목록을 읽어 Day/Week/Agenda를 표시해야 하므로 write-only access는 기능을 충족하지 못한다. sandbox 빌드는 calendars entitlement와 full-access usage description을 포함한다.

UI 원칙:
- 권한이 없으면 왜 필요한지 설명한다.
- 권한 거부 시 System Settings로 가는 복구 경로를 제공한다.
- System Settings에서 돌아와 앱이 active가 되면 권한과 EventKit 데이터를 다시 확인한다.
- unknown status는 crash하지 않고 안전한 안내 상태로 처리한다.
- full access가 철회되면 메모리에 있던 calendar, event, 선택 상태를 즉시 비워 inspector에 이전 일정 정보가 남지 않게 한다.
- Xcode Preview는 실제 EventKit provider를 만들지 않는 no-access provider를 사용한다.

## 결정 4: Read-only 캘린더도 Event Brief는 붙일 수 있다

읽기 전용 캘린더의 원본 이벤트는 수정할 수 없다.
하지만 KaosCal local context는 사용자의 Mac에 저장되는 별도 데이터이므로 Event Brief는 붙일 수 있다.

UI:
- 원본 일정 편집 버튼 대신 typed restriction reason을 표시한다.
- Source badge에 role·account type·editable/restriction을 표시하고 calendar/source text를 별도로 유지한다.
- 수정 불가 이유는 invitation → attendee meeting → subscribed → birthdays → provider-reported read-only의 typed 우선순위를 사용한다.
- 모든 사유는 원본을 수정하지 못해도 KaosCal 메모와 체크리스트는 local에 저장할 수 있음을 함께 설명한다.
- EventKit이 공유 owner/admin ACL의 구체 원인을 주지 않으면 Exchange·CalDAV·iCloud의 read-only 사유를 추측하지 않고 “macOS Calendar가 read-only로 보고함”으로 한정한다.

## 결정 5: 종일·시간대·반복 일정은 명시적 의미를 가진다

- 종일 일정은 시각이 아니라 날짜 범위로 표시·저장한다.
- `timeZone == nil`은 floating time으로 구분한다.
- 시간대 변경 전에는 `현지 시각 유지`와 `동일 시점 유지` 결과를 미리 보여 준다.
- 모든 반복 occurrence를 표시한다.
- 기본 일·주·월·년 반복, interval, 종료, 주간 요일을 손실 없이 표현할 수 있을 때만 생성·편집한다.
- EventKit은 비반복 `EKEvent`에도 `startDate` 지정 뒤 `occurrenceDate == startDate`를 합성할 수 있다. 따라서 raw `occurrenceDate` 존재 여부는 반복 판정 근거가 아니다.
- provider 경계에서 `DisplayEvent.isRecurring = EKEvent.hasRecurrenceRules || EKEvent.isDetached`로 판정하고, 비반복이면 `DisplayEvent.occurrenceDate`를 `nil`로 정규화한다. 이후 반복 소속·scope 요구·write routing은 `DisplayEvent.isRecurring`만 사용한다.
- `occurrenceDate`는 반복 경로에 들어간 뒤 occurrence lookup·identity reconciliation에만 사용한다. detached occurrence는 recurrence rule이 없어도 반복 series의 occurrence이므로 `isDetached`로 반복에 포함한다.
- 반복 변경 범위는 EventKit의 의미에 맞춰 `이번 일정` 또는 `이번 이후`로 표시하고 명시적 선택 전에는 write하지 않는다.
- KaosCal이 안전하게 표현할 수 없는 복잡한 서버 규칙은 읽고 보존한다. 해당 occurrence의 일반 필드는 `이번 일정`으로 rule을 건드리지 않고 수정할 수 있지만, rule 자체와 `이번 이후` 변경은 Calendar.app으로 안내한다.
- Event Brief는 기본적으로 occurrence별이다.

## 결정 6: 변경 감지는 보수적으로 한다

EventKit 변경 알림이나 fetch 결과를 통해 원본 이벤트 변경을 감지한다.
감지 실패를 데이터 삭제로 해석하지 않는다.

`EKEventStoreChanged`를 받으면 기존 event object를 stale로 취급하고 마지막으로 성공한 loaded interval을 다시 fetch한다. 알림은 어떤 일정이 바뀌었는지 알려 주지 않는다. 연속 알림은 250ms 동안 병합해 같은 범위를 불필요하게 반복 조회하지 않는다.

Phase 7A는 원본 부재와 무관한 시간 lifecycle만 구현한다. active occurrence의 유효 종료를 기준으로 scheduled/completed를 갱신하고, cancelled/orphaned는 덮어쓰지 않는다.

구현된 Phase 7B의 부재 확인 계약:
- 일반 구간 fetch에서 한 번 찾지 못한 결과는 상태 전이나 확인 횟수의 근거로 쓰지 않는다.
- 사용자가 원본 열기를 요청하면 저장 link의 strong event/item/external identifiers와 occurrence anchor로 전용 lookup한다. active link의 첫 명시적 `notFound`만 `missing`으로 기록한다.
- 이미 missing인 항목을 사용자가 `Recheck`했고 lookup도 `notFound`일 때만 orphan 보관 확인을 제공한다. 이 두 번째 결과만으로 DB를 orphaned로 만들지는 않는다.
- 권한·provider 오류, candidate, ambiguous, calendar unavailable, invalid stored link와 recurring occurrence unavailable 같은 inconclusive 결과는 missing/orphan 근거가 아니며 상태를 바꾸지 않는다.
- recurring lookup은 zoned instant 또는 all-day/floating civil anchor가 정확히 같은 occurrence만 strong match로 인정한다. 어느 calendar에서든 강한 identifier seed의 recurrence/occurrence가 저장 anchor와 맞지 않으면 `strongIdentifierOccurrenceMismatch` 또는 `recurringOccurrenceUnavailable` inconclusive이며 sibling occurrence를 자동 선택하지 않는다.
- 살아 있는 recurring series의 first-occurrence seed는 exact occurrence가 범위 밖으로 이동했는지 삭제됐는지 구분하는 tombstone이 아니다. bounded EventKit 조회로 둘을 구분할 수 없는 동안에는 자동 missing/orphan을 제공하지 않고 manual exact-occurrence relink만 제공한다.
- 유일한 strong `.found`는 missing을 active로 복구한다. 유일한 EventKit canceled match는 부재가 아니라 cancellation 증거로 다뤄 active link와 local Brief를 유지한 채 context를 cancelled로 만든다. 이후 non-cancelled `.found`는 cancelled를 해제하고 scheduled/completed를 다시 계산한다. 이 provider 관찰에는 `cancelled` change log를 쓰지 않으며 Phase 7C 원본 삭제와 구분한다.
- Keep as orphan, Relink, Delete local Brief는 명시적으로 분리한다. local 삭제는 missing/orphaned SQLite context만 cascade 삭제하고 EventKit 삭제를 호출하지 않는다.
- Relink는 선택 event를 provider에서 다시 strong lookup해 유일한 `.found`/`.cancelled`인지 최종 검증한다. 선택 당시 `EventLink`와 현재 row의 equality CAS, strong-ID 존재와 다른 context 충돌 검사를 통과한 뒤 snapshot/lifecycle/Undo supersede/`relinked` log를 하나의 SQLite transaction으로 저장한다.
- Phase 7B는 schema migration을 추가하지 않았다. relink before log의 `originalNotes`는 v1 link가 원본 EventKit notes를 저장하지 않았기 때문에 nil/unavailable이며, local Event Brief notes를 대신 넣지 않는다.
- 구현된 Phase 7C linked original delete는 active Brief의 notes/tasks/history, saved `EventLink`와 deletion snapshot을 read-only로 준비하고 별도 final Confirm 뒤에만 EventKit을 호출한다. Confirm 직전 expected-link/snapshot을 다시 검사한다.
- successful delete receipt 뒤 context `cancelled`, link `orphaned`, available Undo supersede와 unavailable `cancelled` log를 한 SQLite transaction으로 finalize한다. log before/after는 같은 saved-link snapshot이고 v1에 없는 `originalNotes`는 nil/unavailable이다. local notes/tasks는 보존하며 Delete Undo는 없다.
- deleted-original 표시는 status pair만으로 결정하지 않는다. 현재 context에 unavailable `cancelled` log가 있고 그 뒤 `(created_at, rowid)`상 더 최신 `relinked`가 없어야 한다. relink는 과거 deletion provenance를 무효화하므로 이후 같은 상태쌍이 다시 생겨도 새 KaosCal deletion log 없이는 일반 orphan이다.
- nonrecurring은 log `single`, recurring occurrence는 `this_event`만 허용한다. linked `futureEvents`, attendee meeting/invitation과 read-only 원본은 계속 provider 전에 차단한다.
- EventKit 성공 뒤 receipt/local finalize가 실패하거나 둘 사이 crash가 나면 원본을 자동 복원하거나 Delete를 재시도하지 않는다. review를 닫고 refresh하며 local Brief 보존과 false log 없음, 실제 외부 성공 범위를 알린다. Phase 7C는 기존 v1/v2 값만 써 migration이 없다.

후속 live gate에서 비반복 linked original delete의 EventKit 삭제, Calendar.app/Outlook 부재와 local Brief/task 보존은 확인했다. 반복 `thisEvent` mutation과 retained local Brief cleanup 화면은 macOS session lock으로 미검증이며 비반복 결과로 대체하지 않는다.

세부 경계는 [ADR-012](adr/ADR-012-lifecycle-after-review-and-orphan-confirmation.md)를 따른다.

## 결정 7: EventKit ID는 영구 ID가 아니다

`eventIdentifier`는 빠른 lookup 키로만 사용한다.
영구 연결은 여러 snapshot과 fingerprint를 함께 사용한다.

저장할 키:
- eventIdentifier
- calendarItemIdentifier
- calendarItemExternalIdentifier
- calendarIdentifier
- source title
- title/start/end/location snapshot
- fingerprint
- is_all_day, time_semantics, time_zone_identifier
- recurrence series identifier, occurrence date, occurrence identity key, occurrence local components, is_detached

구현된 영속 resolver는 zoned 반복 occurrence를 절대 시점 키로, all-day/floating occurrence를 canonical civil-components 키로 구분한다. 강한 identifier match만 자동 연결·snapshot 갱신하고 exact snapshot/fingerprint는 사용자 확인 후보로만 반환한다. 과거 synthetic occurrence anchor 오분류로 recurring identity가 저장된 single은 강한 identifier와 전체 snapshot/anchor까지 같은 경우에만 `single:v1`로 정상화한다. legacy 구조와 강한 identifier는 맞지만 snapshot이 달라졌으면 자동 연결하지 않고 confirmation candidate로만 노출한다. 세부 계약은 [ADR-008](adr/ADR-008-local-context-store-and-event-identity.md)을 따른다.

## Phase 1 체크리스트

- full access 권한 요청 화면이 있다.
- 권한 허용 후 Exchange source와 캘린더 목록이 보인다.
- 권한 허용 후 시간·종일·반복 occurrence 이벤트 목록이 보인다.
- 권한 거부 상태가 crash 없이 표시된다.
- read-only 캘린더가 구분된다.
- Event store 변경 알림 후 마지막 loaded interval을 다시 조회한다.
- EventKit read-only 단계에서 local DB를 추가하지 않는다.

## 결정 8: 참석자가 있는 일정은 원본을 건드리지 않는다

초대받은 일정과 사용자가 주최했더라도 참석자가 있는 meeting에는 local Event Brief와 작업을 붙일 수 있다. 그러나 v1은 RSVP, 참석자, organizer, 원본 제목·시간·삭제 변경을 제공하지 않는다. EventKit의 `hasAttendees`가 참이면 외부 알림·취소 부작용을 피하기 위해 Calendar.app에서 수행하도록 안내한다.

## 결정 9: 조회 모델과 새로고침 의미

- 앱 생명주기 동안 하나의 `EKEventStore`를 유지한다.
- EventKit 객체를 UI state에 보관하지 않고 `CalendarSource`와 `DisplayEvent` 값 snapshot으로 변환한다.
- 초기 조회 범위는 실행 시점의 오늘을 기준으로 -30일~+90일이다.
- 사용자가 loaded interval 밖으로 이동하면 visible interval 앞 30일과 뒤 90일을 포함하는 범위를 다시 가져온다. 현재 화면으로 되돌아오면 대기 중인 먼 범위 조회를 취소한다.
- toolbar의 `Reload events`는 마지막 loaded interval의 현재 EventKit snapshot을 다시 조회한다. Exchange 서버 동기화 자체는 macOS Calendar가 담당하며 KaosCal이 강제하지 않는다.
- EventKit 종일 일정의 raw `endDate`는 다음 날 자정뿐 아니라 마지막 날 `23:59:59`로도 관찰되므로 provider 경계에서 날짜 배타 종료 자정으로 정규화한다. Agenda와 inspector는 이 배타 종료에서 하루를 빼 사람이 보는 포함 종료 날짜를 표시한다.
- 날짜가 바뀌는 시간 일정은 시작과 종료 양쪽 날짜를 표시한다.
- calendar color는 `EKCalendar.cgColor`를 sRGB 값 snapshot으로 바꾸고 rail에만 사용한다.
- all-day/floating local components에는 원래 calendar identifier를 보존한다. 표시 달력이 Buddhist/Japanese 등이어도 재구성 날짜가 이동하지 않게 하고, 표시 time zone만 적용한다.
- UI occurrence identity는 calendar identifier + 가능한 EventKit item identifier + 반복 occurrence anchor 조합이다. all-day/floating은 raw UTC `Date` 대신 local occurrence anchor를 사용한다. 영속 Event Brief 복구는 결정 7의 별도 resolver를 따른다.
- 승인된 `CAL-007` 후속 조회는 mini month grid 첫날 시작부터 42번째 날 다음 날 시작까지의 coverage를 성공한 뒤에만 일정 존재를 확정한다. 기존 loaded interval과 합쳐 조회하거나 별도 cache를 사용해 Day/Week/Agenda snapshot을 축소·교체하지 않아야 하며, 빠른 월 탐색에서 취소됐거나 오래된 응답이 최신 grid를 덮어서는 안 된다.
- coverage가 불완전하거나 실패하면 부분 dot을 노출하거나 dot 부재를 `일정 없음`으로 해석하지 않는다. 이 조회는 read-only이며 EventKit create/update/delete를 호출하지 않는다.

## 결정 10: 원본 write는 최신 강한 identity와 변경 필드만 사용한다

- Phase 5는 full access, writable calendar, attendee 없음, 비반복 일정으로 원본 write를 시작했다. Phase 6은 새 basic recurrence 생성과 기존 반복 occurrence의 scope-aware update/delete를 추가했다.
- 기존 일정은 편집 시작 객체를 저장하지 않고 같은 `EKEventStore`에서 strong identifier와 series/occurrence anchor로 다시 찾는다. 반복은 civil/instant 의미에 맞는 선택 occurrence 후보가 유일할 때만 쓴다.
- 다시 읽은 지원 필드가 편집 시작 snapshot과 다르면 외부 변경으로 중단한다. zoned 시간은 absolute instant+zone, all-day/floating은 civil components로 비교한다.
- no-op은 save하지 않고 변경 필드만 patch한다. 변경하지 않은 structured location, alarm, URL 같은 editor 밖 metadata를 불필요하게 다시 쓰지 않는다.
- 원본 notes는 명시적 editor field로만 `EKEvent.notes`에 쓰고 local Event Brief notes/tasks와 분리한다.
- 종일 종료는 배타 자정이다. draft가 포착한 reference time zone을 사용하고, 저장 시 기본 zone이 달라졌으면 all-day/floating wall components를 현재 zone에 rebase해 civil 값을 유지한다.
- time zone 변경은 preserve-local/preserve-instant를 구분하고 DST gap/overlap의 모호한 local time은 자동 보정하지 않는다.
- linked same-calendar update·calendar 이동·안전한 `thisEvent`는 EventKit receipt로 기존 context snapshot을 rebind한다. linked delete는 Phase 7C의 별도 saved-link review/finalize로 열었고, linked `futureEvents`와 attendee/invitation delete는 계속 차단한다.
- EventKit 성공 뒤 SQLite rebind 실패는 부분 성공으로 알리고 local 데이터를 삭제하지 않는다.

전체 계약은 [ADR-010](adr/ADR-010-original-event-write-safety.md)을 따른다. 실제 Exchange save/remove 통과 여부는 [Exchange Compatibility](exchange-compatibility.md)에서만 판정한다.

## 결정 11: 반복·linked move는 impact 확인과 reconciliation 계획이 먼저다

아래 Phase 6 계약은 코드와 121-test 자동 gate로 구현·검증했다. 실계정 Exchange 통과 상태는 여전히 별도다.

- 기존 반복 occurrence update/move/delete는 `thisEvent` 또는 `futureEvents` scope가 필수다. UI에는 각각 `이번 일정`, `이번 이후`로 표시한다.
- `thisEvent`는 선택 occurrence가 detached될 수 있음을 preview한다. 이미 detached인 occurrence의 `futureEvents`는 차단한다.
- 기존 recurrence rule 변경은 `futureEvents`에서만 허용한다. `thisEvent`는 occurrence 상세 변경만 가능하고, linked series는 초기 Phase 6에서 future scope 자체가 차단되므로 rule 변경도 Calendar.app으로 보낸다.
- 여러 recurrence rule이나 KaosCal이 손실 없이 왕복할 수 없는 복잡한 rule은 읽고 보존한다. `thisEvent`의 ordinary-field patch는 recurrenceRules를 쓰지 않는 조건으로 허용하지만, `futureEvents`와 rule 변경은 Calendar.app으로 안내한다.
- 새 일정에는 지원 가능한 basic rule을 만들 수 있지만 기존 single event를 series로 변환하는 control은 초기 Phase 6에서 제공하지 않는다.
- attendee가 있는 meeting과 invitation은 scope와 무관하게 Calendar.app 전용이다.
- 반복 write, calendar move, 기존 일정의 시간 의미 변경은 immutable impact preview를 보여 주고 사용자가 Confirm한 뒤에만 provider를 호출한다. linked context가 있으면 유지할 local 항목을 함께 보여 준다. Cancel·validation 실패·no-op에는 EventKit write와 local log가 없다.
- confirm 뒤에도 현재 full access, source/target writable, strong identity, fresh supported-field snapshot을 다시 검사한다.
- linked `thisEvent` move는 선택 context 하나를 receipt에 rebind한다. Phase 6의 첫 안전 범위는 series split 뒤 여러 context를 재연결하는 기능을 제공하지 않으므로 linked `futureEvents`를 전부 write 전에 차단한다. 나중에 열더라도 영향받는 local context 전부를 열거하고 각 context를 강하게 재연결할 수 있어야 하며 weak·ambiguous·missing이 하나라도 있으면 계속 차단한다.
- Phase 7C는 linked nonrecurring `single`과 recurring occurrence `thisEvent` delete를 saved-link impact review와 final Confirm 뒤에 허용한다. linked `futureEvents`는 multi-context reconciliation이 없어 계속 차단한다.
- linked write 성공 뒤 context rebind와 `event_change_log` append는 하나의 SQLite transaction이다. Phase 7C delete는 context/link status, Undo supersede와 cancellation log를 하나의 local transaction으로 묶는다. EventKit과 이 local transaction은 원자적이지 않으므로 EventKit만 성공한 부분 성공을 숨기거나 자동 rollback하지 않는다.
- EventKit save 후 identifier churn으로 post-save occurrence를 강하게 재탐색하지 못하면 `CalendarEventMutationPartialSuccess`로 전파한다. UI는 editor/review를 닫고 refresh하며 동일 명령을 재시도하지 말고 Calendar.app에서 확인하도록 안내한다. local rebind·log·Undo는 수행하지 않고 Event Brief를 보존한다.
- change log scope는 `single`, `this_event`, `future_events`를 구분한다. 실패·취소·단순 관찰은 기록하지 않는다.
- persistent log는 audit/history이며 Undo 권한 자체가 아니다. Undo는 같은 process session의 직전 linked nonrecurring `single` calendar/time mutation 한 건만, 현재 원본이 logged after snapshot과 같을 때 역방향 write로 실행한다. unlinked·details-only·반복·detached·delete는 Undo하지 않는다.
- provider 경계에서는 `isRecurring`이 canonical 판정이지만 persisted Undo payload를 복원·검증하는 경로의 recurrence·detached·occurrence 중복 검사는 과거 데이터와 불일치에 대비한 방어 조건으로 유지한다. 이 중복 검사를 일반 scope routing의 판정 규칙으로 역전파하지 않는다.

세부 schema, 확인 기준과 무효화 조건은 [ADR-011](adr/ADR-011-recurrence-move-change-log-and-session-undo.md)을 따른다. Exchange `EKSpan`·series split·identifier churn은 `KC-E4` 수동 결과 전까지 지원 통과로 선언하지 않는다.

## 결정 12: Multi-calendar clarity는 EventKit 원본 위의 local/read-only projection이다

- `CalendarSource`와 `DisplayEvent`는 EventKit raw snapshot으로 유지한다. Work/Personal 같은 사용자 역할을 원본 calendar title·notes·color에 쓰지 않는다.
- role은 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`다. subscribed/birthdays만 `Subscription`으로 추론하고 Exchange·CalDAV·iCloud·local은 이름이나 account type으로 용도를 추측하지 않아 `Other`다.
- 현재 source list에 calendar가 없고 exact explicit override도 없으면 저장된 event/task account type snapshot으로 역할을 추측하지 않고 `Other`로 표시한다.
- 사용자가 바꾼 role만 additive `v3_calendar_clarity`/`calendar_preferences`에 sparse upsert한다. EventKit fetch는 row를 만들지 않고 role 변경은 `CalendarProviding` write를 호출하지 않는다.
- Phase 8 당시 Calendar Set은 `All`과 role별 virtual view filter였다. 이후 role filter는 `Smart Role Filter`로 이름을 분리하고 `v9_saved_calendar_sets`의 사용자 saved Set을 추가했다. saved Set은 exact calendar identifier membership이며 global Enabled와 교집합으로 visibility만 좁힌다. raw fetch, local context observation, recovery lookup, Task Center DB query와 editor writable destination은 필터링하지 않는다.
- duplicate candidate는 다른 calendar의 정규화 title이 같고 timed start/end가 각각 15분 이내이거나 all-day civil range가 같은 경우의 비영속 read projection이다. fetch당 한 번 candidate index를 만들고 UI는 event ID로 O(1) 조회한다. 같은 strong identity/occurrence는 제외하고 자동 merge·hide·delete·EventKit write는 제공하지 않는다.
- role preference의 source/calendar title snapshot은 자동 identifier-churn 재연결 근거가 아니다. exact calendar identifier가 달라지면 이름 유사성만으로 role을 승계하지 않는다.
- AppState 원본 write preflight는 UI에 표시하는 것과 같은 `CalendarWriteRestriction`을 직접 throw한다. provider의 Confirm 후 fresh permission check는 독립 방어선으로 유지한다.

saved Set의 persistence·missing membership·명시적 rebind·selection fallback 세부 계약은
[ADR-018](adr/ADR-018-saved-calendar-sets.md), 기존 role/restriction 계약은
[ADR-014](adr/ADR-014-multi-calendar-clarity.md)를 따른다. shared read-only Exchange fixture의 실제 permission reason과 긴 source/role 조합의 화면 표시는 아직 live visual gate를 통과하지 않았으며 session lock으로 막힌 화면 gate를 자동 결과로 대체하지 않는다.
