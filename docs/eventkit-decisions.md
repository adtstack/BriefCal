# EventKit Decisions

## 목적

KaosCal v1은 직접 sync engine을 만들지 않고 EventKit을 통해 macOS Calendar와 연결한다.
이 문서는 EventKit 사용에서 제품 품질과 데이터 안전성에 영향을 주는 결정을 고정한다.

## 결정 1: EventKit은 원본 일정의 유일한 v1 입출력 계층이다

v1에서는 Google Calendar API, Microsoft Graph, CalDAV, iCloud API를 직접 구현하지 않는다.
사용자는 macOS System Settings와 Calendar.app에 이미 연결된 계정을 통해 일정을 사용한다.

이유:
- v1의 차별점은 sync coverage가 아니라 Event Brief다.
- 직접 sync를 만들면 인증, conflict, recurrence, rate limit, offline queue가 제품의 중심을 밀어낸다.
- macOS-first 제품답게 시스템 계정과 권한 모델을 활용한다.

## 결정 2: KaosCal 고유 데이터는 EventKit에 저장하지 않는다

EventKit 이벤트에는 원본 일정 데이터만 저장한다.
Before/During/After 체크리스트, KaosCal notes, change log, Event Brief 상태는 SQLite에 저장한다.

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

UI 원칙:
- 권한이 없으면 왜 필요한지 설명한다.
- 권한 거부 시 System Settings로 가는 복구 경로를 제공한다.
- unknown status는 crash하지 않고 안전한 안내 상태로 처리한다.

## 결정 4: Read-only 캘린더도 Event Brief는 붙일 수 있다

읽기 전용 캘린더의 원본 이벤트는 수정할 수 없다.
하지만 KaosCal local context는 사용자의 Mac에 저장되는 별도 데이터이므로 Event Brief는 붙일 수 있다.

UI:
- 원본 일정 편집 버튼은 비활성화한다.
- Source badge에 read-only 상태를 표시한다.
- "이 캘린더는 원본 일정을 수정할 수 없지만 KaosCal 메모와 체크리스트는 저장할 수 있습니다." 같은 문구를 사용한다.

## 결정 5: 반복 일정은 v1에서 단일 occurrence 중심으로 제한한다

반복 일정 전체 편집은 v1 범위 밖이다.
v1에서는 선택한 occurrence의 표시와 제한적 편집을 우선한다.

원칙:
- 반복 전체 변경 UI를 만들기 전에는 전체 series 변경을 제공하지 않는다.
- 사용자가 반복 이벤트를 편집하려 하면 영향 범위를 명확히 보여준다.
- 구현이 불확실한 경우 Calendar.app에서 편집하도록 안내한다.

## 결정 6: 변경 감지는 보수적으로 한다

EventKit 변경 알림이나 fetch 결과를 통해 원본 이벤트 변경을 감지한다.
감지 실패를 데이터 삭제로 해석하지 않는다.

상태 전환:
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

## Phase 1 체크리스트

- 권한 요청 화면이 있다.
- 권한 허용 후 캘린더 목록이 보인다.
- 권한 허용 후 이벤트 목록이 보인다.
- 권한 거부 상태가 crash 없이 표시된다.
- read-only 캘린더가 구분된다.
- EventKit read-only 단계에서 local DB를 추가하지 않는다.

