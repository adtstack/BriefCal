# KaosCal

KaosCal은 macOS Calendar에 이미 연결된 일정을 읽고 편집하면서, 각 일정의 준비물·메모·후속 작업을 로컬에 보존하는 macOS 앱이다.

현재 개발 단계, 최신 자동·Release 증거와 아직 닫히지 않은 live/manual gate는
[Current Status](docs/current-status.md)를 단일 기준으로 사용한다. 과거 검증 결과는
[Implementation Log](docs/implementation-log.md), Exchange 지원 판정은
[Exchange Compatibility](docs/exchange-compatibility.md)에 분리해 보존한다.

## 제품 범위

- macOS 14 이상
- macOS Calendar에 구성된 Exchange 캘린더를 우선 검증 대상으로 하는 EventKit 앱
- Day, Week, Agenda 캘린더, Sidebar mini month와 Task Center
- 종일 일정, 시간대, 반복 일정의 안전한 표시·편집
- active Event Brief와 KaosCal 작업은 로컬 SQLite에 저장. 명시적 export ZIP은 사용자가 고른 로컬·외장·cloud 폴더에 plaintext로 저장 가능

상세 범위와 제외 범위는 [v1-scope.md](docs/v1-scope.md)를, 결정 근거는 [ADR](docs/adr/README.md)을 확인한다.

## 사용자 안내

설치·첫 실행·권한·주요 기능과 로컬 데이터 관리는 [User Guide](docs/user-guide.md),
현재 제한과 우회 방법은 [Known Issues](docs/known-issues.md)를 따른다. 데이터 처리와
보안 보고 경계는 [Privacy](PRIVACY.md)와 [Security](SECURITY.md)에 정리한다.

## 개발 시작 전 준비

전체 Xcode와 테스트 전용 Exchange 캘린더가 필요하다. 자격 증명이나 실제 회사 일정을 공유하지 않는다. 자세한 준비물은 [developer-setup.md](docs/developer-setup.md)에 있다.

## 빌드와 테스트

```sh
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO test
```

EventKit 수동 QA에는 Calendar entitlement가 포함된 서명 앱이 필요하므로 `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES`로 로컬 서명 빌드를 만든다. 실제 검증 명령과 결과는 [implementation-log.md](docs/implementation-log.md)에 남긴다.

첫 실행에서는 앱 안의 `Allow Full Calendar Access`를 누른 뒤 macOS 권한 창에서 허용한다. 사용자가 권한을 허용했다고 보고했더라도 실행 중인 최신 서명 앱에 `Full calendar access`가 표시되는지 별도로 확인한다. 계정 비밀번호나 MFA 코드는 KaosCal에 입력하지 않는다. toolbar의 `Reload events`는 macOS EventKit의 현재 로컬 데이터를 다시 읽을 뿐 Exchange 원격 동기화를 강제하지 않는다.

환경변수에 Exchange 계정, 비밀번호, MFA, OAuth token을 넣지 않는다. 앱은 macOS Internet Accounts에 이미 로그인된 계정을 EventKit으로 사용한다. 로컬 Context DB는 앱 sandbox의 Application Support 아래 자동 생성된다.

## 문서 운영

사용자에게 보이는 동작, 데이터 모델, 지원 범위가 바뀌면 같은 변경에서 ADR, v1 범위,
QA 기준과 구현 로그를 함께 갱신한다. 현재 단계·최신 test count·열린 gate의 요약 판정은
[Current Status](docs/current-status.md)를 기준으로 하고, exact artifact와 실행 증거는 QA,
Implementation Log와 Exchange Compatibility에 보존한다. 상세 규칙은
[ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 정의한다.
