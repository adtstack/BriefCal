# Exchange Compatibility

> 상태: 검증 전
> 제품 대상: macOS Calendar에 구성된 Exchange Online
> 현재 테스트 환경: Exchange backend 종류 미확인, 수정 가능한 `KAOS-TEST` calendar
> 마지막 갱신: 2026-07-10

## 지원 선언 기준

KaosCal은 추측으로 Exchange 기능을 지원한다고 선언하지 않는다. 아래 매트릭스에서 실제 macOS·Exchange 조합으로 통과한 항목만 베타 지원 범위에 넣는다.

| 기능 | 현재 테스트 환경 | 상태 | 증거 |
| --- | --- | --- | --- |
| full calendar access | 미검증 | 대기 | Phase 1 수동 테스트 |
| Exchange source·calendar 식별 | 미검증 | 대기 | Phase 1 수동 테스트 |
| editable calendar 확인 | `KAOS-TEST` | 사용자 확인 | 수정 가능하다고 확인 |
| read-only 구분 | 미검증 | 대기 | Viewer calendar 미준비 |
| 시간 일정 조회 | 미검증 | 대기 | KC-E1 |
| 종일·다일 일정 조회 | 미검증 | 대기 | KC-E2 |
| 시간대/DST 표시·편집 | 미검증 | 대기 | KC-E3 |
| 반복 occurrence 조회 | 미검증 | 대기 | KC-E4 |
| 이번 일정·이번 이후 반복 변경 | 미검증 | 대기 | KC-E4 |
| 외부 변경 알림 후 재조회 | 미검증 | 대기 | Calendar.app/Outlook 변경 |
| 초대 일정 local-only Brief | 미검증 | 대기 | KC-E6 |

## 검증 규칙

- 캘린더를 읽으려면 write-only가 아닌 full access가 필요하다.
- 권한 승인 전에 event fetch를 시도했다면 EventKit store를 재설정하고 다시 조회한다.
- 변경 알림은 변경 세부를 제공하지 않으므로 현재 화면의 날짜 범위를 다시 fetch한다.
- `allowsContentModifications == false`인 경우 원본 일정 변경 UI를 제공하지 않는다.
- 네트워크 끊김·동기화 지연은 원본 삭제로 판단하지 않는다.
- 원격 Exchange 이벤트에 KaosCal metadata를 쓰지 않는다.

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
