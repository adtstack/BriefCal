# ADR-001: macOS 14+와 Exchange/EventKit 경계

> 상태: Accepted
> 날짜: 2026-07-10

## 배경

KaosCal은 Exchange를 우선 검증해야 하지만, Microsoft OAuth·Graph·EWS를 자체 구현하면 인증과 동기화가 제품 중심을 대체한다.

## 결정

- 최소 지원 OS는 macOS 14다.
- 원본 일정 입출력은 EventKit만 사용한다.
- 지원 대상으로는 macOS Calendar에 구성된 Exchange Online calendar를 우선한다.
- 앱은 이벤트를 읽어야 하므로 full calendar access를 요청한다. write-only access는 지원하지 않는다.
- sandbox 빌드에는 Calendar entitlement와 full-access usage description을 넣는다.
- Exchange Online 외 환경은 compatibility matrix에서 검증하기 전 지원을 약속하지 않는다.

## 결과

- Microsoft 자격 증명은 앱이나 저장소에 저장하지 않는다.
- 실제 권한과 수정 가능 여부는 `EKCalendar.allowsContentModifications`로 결정한다.
- full access 거부·제한·기존 write-only 상태를 별도의 복구 UI로 다룬다.

## 검증

Phase 1에서 `KC-E1`~`KC-E6` fixture로 [Exchange Compatibility](../exchange-compatibility.md)를 채운다.

## 근거

- [Apple: requestFullAccessToEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29)
- [Apple: Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
