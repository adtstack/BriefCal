# Architecture

## 아키텍처 목표

KaosCal은 macOS 14 이상을 대상으로 하는 macOS-first local-first calendar다.
원본 캘린더 이벤트는 사용자의 캘린더 계정이 소유하고, KaosCal은 그 이벤트에 붙는 맥락을 로컬 데이터베이스에 저장한다.

핵심 목표는 세 가지다.

1. macOS Calendar와 자연스럽게 연결된다.
2. Event Brief 데이터가 원본 calendar notes를 오염시키지 않는다.
3. EventKit 식별자가 변해도 가능한 한 Event Brief를 복구한다.

## 기술 선택

| 영역 | 선택 | 이유 |
| --- | --- | --- |
| App | SwiftUI macOS app | Mac 네이티브 UX와 빠른 v1 구현 |
| Calendar access | EventKit | macOS Calendar/Internet Accounts에 연결된 계정을 활용 |
| Local DB | SQLite + GRDB.swift | 구조화된 local-first 저장, migration, 테스트 용이성 |
| State | Observable models / ViewModels | 초기 복잡도를 낮추고 SwiftUI와 자연스럽게 연결 |
| Task Center | Local event tasks + personal tasks | 일정 맥락과 오늘 할 일을 한 흐름에서 확인 |
| Distribution | Direct download first | 서버 없는 one-time license 모델과 잘 맞음 |
| Sync | No custom sync in v1 | 직접 Google/Microsoft/CalDAV sync는 v2 이후 검토 |

빌드 기준은 [ADR-006](adr/ADR-006-native-project-build-baseline.md)을 따른다. 현재 provisional bundle identifier는 `com.adtstack.kaoscal`이다.

## 데이터 소유권

| 데이터 | 소유자 | 저장 위치 |
| --- | --- | --- |
| 일정 제목, 시간, 장소, 참석자, 원본 알림 | Calendar account / EventKit | 사용자의 기존 캘린더 계정 |
| Before/During/After 체크리스트 | KaosCal | Local SQLite |
| KaosCal notes | KaosCal | Local SQLite |
| 변경 기록 | KaosCal | Local SQLite |
| Event Brief 상태 | KaosCal | Local SQLite |
| Personal task | KaosCal | Local SQLite |
| 캘린더 역할과 표시 설정 | KaosCal | Local SQLite |

원칙: KaosCal 고유 데이터는 `EKEvent.notes`에 쓰지 않는다.

## 모듈 구조

```text
KaosCal.app
├─ App/
│  ├─ KaosCalApp.swift
│  └─ AppState.swift
├─ CalendarKit/
│  ├─ CalendarProvider.swift
│  ├─ EventKitProvider.swift
│  ├─ CalendarSource.swift
│  ├─ DisplayEvent.swift
│  └─ EventIdentityResolver.swift
├─ ContextStore/
│  ├─ Database.swift
│  ├─ Migrations.swift
│  ├─ EventContextRepository.swift
│  ├─ EventTaskRepository.swift
│  ├─ PersonalTaskRepository.swift
│  └─ ChangeLogRepository.swift
├─ Features/
│  ├─ Onboarding/
│  ├─ CalendarShell/
│  ├─ WeekView/
│  ├─ DayView/
│  ├─ AgendaView/
│  ├─ EventBrief/
│  ├─ TaskCenter/
│  ├─ MoveConfirmation/
│  ├─ AfterReview/
│  └─ Settings/
├─ DesignSystem/
│  ├─ Colors.swift
│  ├─ Typography.swift
│  ├─ EventCard.swift
│  └─ KeyboardShortcuts.swift
└─ Tests/
   ├─ ContextStoreTests/
   ├─ EventIdentityTests/
   └─ ViewModelTests/
```

## 런타임 흐름

1. 앱 시작 시 AppState가 권한 상태와 로컬 DB 상태를 로드한다.
2. CalendarProvider가 EventKit 권한 상태를 확인한다.
3. 권한이 있으면 지정 기간의 이벤트와 캘린더 목록을 가져온다.
4. ContextStore가 로컬 Event Brief 데이터를 로드한다.
5. EventIdentityResolver가 원본 이벤트와 로컬 context를 연결한다.
6. CalendarShell과 Task Center가 Calendar event + KaosCal context + 개인 작업을 함께 표시한다.
7. 사용자가 체크리스트, notes, 개인 작업, 상태를 바꾸면 SQLite만 변경한다.
8. 사용자가 일정 자체를 바꾸면 EventKit을 변경하고 change log를 SQLite에 남긴다.

## CalendarProvider 경계

```swift
protocol CalendarProvider {
    func requestAccess() async throws
    func listCalendars() async throws -> [CalendarSource]
    func fetchEvents(from start: Date, to end: Date) async throws -> [DisplayEvent]
    func createEvent(_ draft: CalendarEventDraft) async throws -> DisplayEvent
    func updateEvent(_ event: DisplayEvent, with draft: CalendarEventDraft) async throws -> DisplayEvent
    func deleteEvent(_ event: DisplayEvent) async throws
}
```

v1에서는 EventKitProvider 하나로 시작한다.
직접 Google/Microsoft/CalDAV adapter는 만들지 않는다.

## Event Brief 경계

Event Brief는 EventKit 이벤트의 부속 UI처럼 보이지만 저장과 생명주기는 KaosCal이 관리한다.

- Event Brief 생성: 이벤트를 단순 선택할 때는 만들지 않고, 사용자가 처음 메모나 작업을 저장할 때 local context를 만든다.
- Event Brief 수정: SQLite에만 쓴다.
- 일정 이동: EventKit 변경 전 확인하고, 확인 후 change log를 남긴다.
- 원본 일정 삭제: local context를 즉시 삭제하지 않고 orphaned 상태로 전환한다.

## Identity resolution

EventKit의 eventIdentifier는 영구 절대값으로 취급하지 않는다. 특히 반복 일정은 occurrence별 정보와 detached 상태를 따로 보존한다.
연결 복구는 아래 순서로 시도한다.

1. `eventIdentifier` 직접 매칭
2. `calendarItemIdentifier` 매칭
3. `calendarItemExternalIdentifier` + calendar identifier 매칭
4. recurrence master + occurrence date + calendar identifier 매칭
5. calendar identifier + 시간 범위 + title/location snapshot 매칭
6. title/start/end/location 기반 fingerprint 후보
7. 실패 시 orphaned context로 유지

## 권한과 read-only 상태

앱은 권한 상태를 제품 경험의 일부로 다룬다. macOS 14 이상에서는 이벤트 목록을 읽기 위해 full calendar access를 명시적으로 요청한다.
권한이 없으면 빈 화면이 아니라 복구 경로를 보여준다.
읽기 전용 캘린더의 이벤트는 Event Brief 편집은 가능하지만 원본 일정 수정 UI는 비활성화한다.

## 오류 처리 원칙

- EventKit 실패는 사용자가 이해할 수 있는 캘린더/권한/네트워크/계정 상태 문구로 바꾼다.
- SQLite migration 실패는 데이터 손실 없이 앱을 중단하고 백업/복구 안내를 제공한다.
- EventKit 변경과 SQLite change log 기록은 하나의 use case로 관리하고, 한쪽만 성공했을 때 재시도·보정·사용자 안내를 남긴다.
- 일정 삭제와 local context 삭제는 별도 명령으로 분리한다.

## 열어둘 결정

- 배포 전 최종 bundle identifier와 signing team
- Mac App Store 배포 여부
- AppKit 보강 범위
- 라이선스 공급자
