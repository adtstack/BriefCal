# ADR-003: 종일·시간대·반복 일정 의미

> 상태: Accepted
> 날짜: 2026-07-10

## 배경

Exchange 일정은 종일, floating time, 고정 시간대, 반복 occurrence를 모두 가질 수 있다. UTC 문자열만 저장하거나 ID 하나로 연결하면 날짜가 밀리거나 다른 반복 일정의 Brief가 섞일 수 있다.

## 결정

- 종일 일정은 시각이 아닌 날짜 범위로 취급하고 all-day lane에 표시한다.
- 시간 일정은 `zoned`와 `floating` 의미를 구분한다. `timeZone == nil`은 floating으로 취급한다.
- 시간대 변경 UI는 항상 새 시간을 미리 보여 주고 `현지 시각 유지`와 `동일 시점 유지`를 명시적으로 선택하게 한다.
- 반복 일정은 모든 occurrence를 표시한다. 기본 일·주·월·년 규칙과 interval, 종료, 주간 요일을 편집한다.
- 반복 변경 범위는 `이번 일정` 또는 `이번 이후`로 표시한다. 안전하게 표현할 수 없는 복잡한 서버 규칙은 보존·표시하고 Calendar.app 편집으로 안내한다.
- Event Brief는 기본적으로 occurrence별이다.

## 결과

이벤트 연결 정보에는 all-day 여부, 시간 의미, 시간대 ID, recurrence master/occurrence 날짜, detached 여부와 snapshot이 필요하다. 정확한 Exchange 변경 범위는 실계정 테스트를 통과한 뒤 열어 간다.

## 근거

- [Apple: EKEvent.isAllDay](https://developer.apple.com/documentation/eventkit/ekevent/isallday)
- [Apple: EKCalendarItem.timeZone](https://developer.apple.com/documentation/eventkit/ekcalendaritem/timezone)
- [Apple: EKSpan](https://developer.apple.com/documentation/eventkit/ekspan)
