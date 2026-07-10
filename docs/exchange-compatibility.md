# Exchange Compatibility

> 상태: Phase 5 비반복 원본 편집 구현·자동 검증 checkpoint / 실계정 EventKit 검증 대기
> 제품 대상: macOS Calendar에 구성된 Exchange Online
> 현재 테스트 환경: Exchange backend 종류 미확인, 사용자가 수정 가능 테스트 대상으로 지정한 `KAOS-TEST` calendar(EventKit 확인 대기)
> 마지막 갱신: 2026-07-11

## 지원 선언 기준

KaosCal은 추측으로 Exchange 기능을 지원한다고 선언하지 않는다. 아래 매트릭스에서 실제 macOS·Exchange 조합으로 통과한 항목만 베타 지원 범위에 넣는다.

| 기능 | 현재 테스트 환경 | 상태 | 증거 |
| --- | --- | --- | --- |
| full calendar access | 설명·요청·거부 복구 구현, 실계정 승인 결과 미확인 | 수동 대기 | 전체 97-test, ad-hoc signed Debug, strict codesign, Calendar entitlement·usage description 통과; 실제 승인 필요 |
| Exchange source·calendar 식별 | `EKSourceType.exchange`·calendar color mapping 구현, 실계정 미확인 | 수동 대기 | `KAOS-TEST` sidebar/color 확인 필요 |
| editable calendar 확인 | 사용자가 `KAOS-TEST`를 수정 가능 테스트 대상으로 지정 | 수동 대기 | 실제 EventKit 노출과 `allowsContentModifications` 확인 필요 |
| read-only 구분 | `allowsContentModifications` mapping·unit state 구현 | blocked | Viewer calendar 미준비, Phase 8 전 해소 |
| 시간 일정 조회 | 미검증 | 대기 | KC-E1 |
| 비반복 일정 생성 | writable/default calendar 선택·draft validation·receipt focus unit 통과 | 실계정 대기 | `KAOS-TEST` 생성 후 Calendar.app 확인 필요 |
| 비반복 일정 수정 | strong re-fetch, fresh snapshot, changed-field patch, linked rebind unit 통과 | 실계정 대기 | KC-E1 제목·시간·장소·원본 notes round-trip 필요 |
| 비반복 일정 삭제 | local Brief 없는 일정만 remove하도록 AppState unit 통과 | 실계정 대기 | `KAOS-TEST` 전용 fixture 삭제와 Calendar.app 확인 필요 |
| calendar 간 이동 | local Brief 없음만 허용, linked는 Phase 6까지 사전 차단 unit 통과 | 실계정 대기 | 두 writable 테스트 calendar와 identifier churn 관찰 필요 |
| 종일·다일 일정 조회 | 자정/`23:59:59` raw end 정규화, 배타 범위·all-day span unit 통과 | 실계정 대기 | KC-E2 |
| 종일 일정 생성·편집 | 포함 종료↔배타 종료, 자정 변환, reference time zone unit 통과 | 실계정 대기 | KC-E2 Calendar.app round-trip 필요 |
| 시간대/DST 표시 | wall-clock 배치, fall-back overlap, floating/non-Gregorian unit 통과 | 실계정 대기 | KC-E3 |
| 시간대 편집 | preserve-local/instant, floating/zoned, DST gap/overlap 차단 unit 통과 | 실계정 대기 | KC-E3 Calendar.app·Exchange 서버 정규화 확인 필요 |
| 반복 occurrence 조회 | occurrence·detached·repeat snapshot과 UI identity unit 통과 | 실계정 대기 | KC-E4 |
| 반복 Event Brief 연결 | zoned instant, all-day/floating civil occurrence, detached local anchor unit 통과 | 실계정 대기 | 실제 KC-E4 identifier 변화 필요 |
| 이번 일정·이번 이후 반복 변경 | 미구현·미검증 | Phase 6 대기 | KC-E4 |
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
- 기존 원본 write는 strong identifier로 최신 비반복 event를 다시 찾고 지원 필드의 stale snapshot이 같을 때만 실행한다.
- fake provider와 SQLite 자동 테스트는 Exchange save/remove 통과 증거가 아니다. Calendar.app round-trip을 별도로 기록한다.
- 네트워크 끊김·동기화 지연은 원본 삭제로 판단하지 않는다.
- 원격 Exchange 이벤트에 KaosCal metadata를 쓰지 않는다.
- Exchange source가 보이더라도 backend를 Exchange Online이라고 추론하지 않는다. 현재 backend는 unknown으로 유지한다.

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
