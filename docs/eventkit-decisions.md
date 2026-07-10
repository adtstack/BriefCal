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
Before/During/After 체크리스트, KaosCal notes, Event Brief 상태는 SQLite에 저장한다. change log는 Phase 6에서 같은 로컬 저장소에 추가한다.

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
- 원본 일정 편집 버튼은 비활성화한다.
- Source badge에 read-only 상태를 표시한다.
- "이 캘린더는 원본 일정을 수정할 수 없지만 KaosCal 메모와 체크리스트는 저장할 수 있습니다." 같은 문구를 사용한다.

## 결정 5: 종일·시간대·반복 일정은 명시적 의미를 가진다

- 종일 일정은 시각이 아니라 날짜 범위로 표시·저장한다.
- `timeZone == nil`은 floating time으로 구분한다.
- 시간대 변경 전에는 `현지 시각 유지`와 `동일 시점 유지` 결과를 미리 보여 준다.
- 모든 반복 occurrence를 표시한다.
- 기본 일·주·월·년 반복, interval, 종료, 주간 요일을 손실 없이 표현할 수 있을 때만 생성·편집한다.
- 반복 변경 범위는 EventKit의 의미에 맞춰 `이번 일정` 또는 `이번 이후`로 표시하고 명시적 선택 전에는 write하지 않는다.
- KaosCal이 안전하게 표현할 수 없는 복잡한 서버 규칙은 읽고 보존한다. 해당 occurrence의 일반 필드는 `이번 일정`으로 rule을 건드리지 않고 수정할 수 있지만, rule 자체와 `이번 이후` 변경은 Calendar.app으로 안내한다.
- Event Brief는 기본적으로 occurrence별이다.

## 결정 6: 변경 감지는 보수적으로 한다

EventKit 변경 알림이나 fetch 결과를 통해 원본 이벤트 변경을 감지한다.
감지 실패를 데이터 삭제로 해석하지 않는다.

`EKEventStoreChanged`를 받으면 기존 event object를 stale로 취급하고 마지막으로 성공한 loaded interval을 다시 fetch한다. 알림은 어떤 일정이 바뀌었는지 알려 주지 않는다. 연속 알림은 250ms 동안 병합해 같은 범위를 불필요하게 반복 조회하지 않는다.

목표 상태 전환(Phase 6~7, 현재 미구현):
- 한 번 찾지 못하면 `missing`
- 복구 후보가 없고 충분한 재확인 후 `orphaned`
- 사용자가 직접 삭제를 승인해야 local context 삭제

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

구현된 영속 resolver는 zoned 반복 occurrence를 절대 시점 키로, all-day/floating occurrence를 canonical civil-components 키로 구분한다. 강한 identifier match만 자동 연결·snapshot 갱신하고 exact snapshot/fingerprint는 사용자 확인 후보로만 반환한다. 세부 계약은 [ADR-008](adr/ADR-008-local-context-store-and-event-identity.md)을 따른다.

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

## 결정 10: 원본 write는 최신 강한 identity와 변경 필드만 사용한다

- Phase 5는 full access, writable calendar, attendee 없음, 비반복 일정으로 원본 write를 시작했다. Phase 6은 새 basic recurrence 생성과 기존 반복 occurrence의 scope-aware update/delete를 추가했다.
- 기존 일정은 편집 시작 객체를 저장하지 않고 같은 `EKEventStore`에서 strong identifier와 series/occurrence anchor로 다시 찾는다. 반복은 civil/instant 의미에 맞는 선택 occurrence 후보가 유일할 때만 쓴다.
- 다시 읽은 지원 필드가 편집 시작 snapshot과 다르면 외부 변경으로 중단한다. zoned 시간은 absolute instant+zone, all-day/floating은 civil components로 비교한다.
- no-op은 save하지 않고 변경 필드만 patch한다. 변경하지 않은 structured location, alarm, URL 같은 editor 밖 metadata를 불필요하게 다시 쓰지 않는다.
- 원본 notes는 명시적 editor field로만 `EKEvent.notes`에 쓰고 local Event Brief notes/tasks와 분리한다.
- 종일 종료는 배타 자정이다. draft가 포착한 reference time zone을 사용하고, 저장 시 기본 zone이 달라졌으면 all-day/floating wall components를 현재 zone에 rebase해 civil 값을 유지한다.
- time zone 변경은 preserve-local/preserve-instant를 구분하고 DST gap/overlap의 모호한 local time은 자동 보정하지 않는다.
- linked same-calendar update·calendar 이동·안전한 `thisEvent`는 EventKit receipt로 기존 context snapshot을 rebind한다. linked `futureEvents`와 linked 삭제는 각각 multi-context reconciliation과 Phase 7 orphan review 전까지 차단한다.
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
- linked delete는 Phase 7 orphan review까지 계속 차단한다. local Brief가 없는 반복 원본만 Phase 6 scoped delete 후보가 될 수 있다.
- linked write 성공 뒤 context rebind와 `event_change_log` append는 하나의 SQLite transaction이다. EventKit과 이 local transaction은 원자적이지 않으므로 EventKit만 성공한 부분 성공을 숨기거나 자동 rollback하지 않는다.
- EventKit save 후 identifier churn으로 post-save occurrence를 강하게 재탐색하지 못하면 `CalendarEventMutationPartialSuccess`로 전파한다. UI는 editor/review를 닫고 refresh하며 동일 명령을 재시도하지 말고 Calendar.app에서 확인하도록 안내한다. local rebind·log·Undo는 수행하지 않고 Event Brief를 보존한다.
- change log scope는 `single`, `this_event`, `future_events`를 구분한다. 실패·취소·단순 관찰은 기록하지 않는다.
- persistent log는 audit/history이며 Undo 권한 자체가 아니다. Undo는 같은 process session의 직전 linked nonrecurring `single` calendar/time mutation 한 건만, 현재 원본이 logged after snapshot과 같을 때 역방향 write로 실행한다. unlinked·details-only·반복·detached·delete는 Undo하지 않는다.

세부 schema, 확인 기준과 무효화 조건은 [ADR-011](adr/ADR-011-recurrence-move-change-log-and-session-undo.md)을 따른다. Exchange `EKSpan`·series split·identifier churn은 `KC-E4` 수동 결과 전까지 지원 통과로 선언하지 않는다.
