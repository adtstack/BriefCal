# KaosCal

KaosCal은 macOS Calendar에 이미 연결된 일정을 읽고 편집하면서, 각 일정의 준비물·메모·후속 작업을 로컬에 보존하는 macOS 앱이다.

현재 상태: **Phase 0 완료 — Phase 1 EventKit/Exchange 읽기 구현 준비**. 빌드 가능한 macOS SwiftUI 앱과 단위 테스트 타깃이 있다.

## 제품 범위

- macOS 14 이상
- macOS Calendar에 구성된 Exchange 캘린더를 우선 검증 대상으로 하는 EventKit 앱
- Day, Week, Agenda 캘린더와 Task Center
- 종일 일정, 시간대, 반복 일정의 안전한 표시·편집
- Event Brief와 KaosCal 작업은 로컬 SQLite에만 저장

상세 범위와 제외 범위는 [v1-scope.md](docs/v1-scope.md)를, 결정 근거는 [ADR](docs/adr/README.md)을 확인한다.

## 시작 전 준비

전체 Xcode와 테스트 전용 Exchange 캘린더가 필요하다. 자격 증명이나 실제 회사 일정을 공유하지 않는다. 자세한 준비물은 [developer-setup.md](docs/developer-setup.md)에 있다.

## 빌드와 테스트

```sh
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData CODE_SIGNING_ALLOWED=NO test
```

EventKit 수동 QA에는 Calendar entitlement가 포함된 서명 앱이 필요하므로 `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES`로 로컬 서명 빌드를 만든다. 실제 검증 명령과 결과는 [implementation-log.md](docs/implementation-log.md)에 남긴다.

## 문서 운영

사용자에게 보이는 동작, 데이터 모델, 지원 범위가 바뀌면 같은 변경에서 ADR, v1 범위, QA 기준, 구현 로그를 함께 갱신한다. 이 규칙은 [ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 정의한다.
