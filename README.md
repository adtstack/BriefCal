# KaosCal

KaosCal은 macOS Calendar에 이미 연결된 일정을 읽고 편집하면서, 각 일정의 준비물·메모·후속 작업을 로컬에 보존하는 macOS 앱이다.
AI와 KaosCal 계정·서버·Cloud 없이 이 Mac에서 실행되며, Calendar는 EventKit, 사용자가
연결한 event task는 해당 provider와 이 Mac이 직접 동기화한다.
제품의 영구 local-only 경계는
[ADR-019](docs/adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md)를 따른다.

현행 제품 동작, 시스템 불변식과 요구사항별 인수 기준은
[제품·시스템 스펙](docs/specification.md)을 기준으로 한다.
현재 개발 단계, 최신 자동·Release 증거와 아직 닫히지 않은 live/manual gate는
[Current Status](docs/current-status.md)를 단일 기준으로 사용한다. 과거 검증 결과는
[Implementation Log](docs/implementation-log.md), Exchange 지원 판정은
[Exchange Compatibility](docs/exchange-compatibility.md)에 분리해 보존한다.

v1 기능 개발은 [v1 동결 결정](docs/v1-freeze.md)에 따라 종료했다. 이후 외부 task
provider와 통합 캘린더 작업은 [v2 실행계획](docs/v2-execution-plan.md)과
[단계별 세부문서](docs/v2/README.md)를 기준으로 한다.

## 제품 범위

- macOS 14 이상
- macOS Calendar에 구성된 Exchange 캘린더를 우선 검증 대상으로 하는 EventKit 앱
- Day, Week, Month, Agenda 캘린더, Sidebar mini month와 Task Center
- 본문 Month의 4~6주 grid, 일정 제목·시간, 주 경계 multi-day segment와 `+N` overflow
- 종일 일정, 시간대, 반복 일정의 안전한 표시·편집
- Apple Reminders, Google Tasks, Todoist와 Microsoft To Do의 capability-aware 작업 관리,
  Apple 목록 이동·Todoist project/section 이동, 통합 검색·planning과 Calendar time block
- active Event Brief와 KaosCal 작업은 이 Mac의 로컬 SQLite에만 저장. 명시적 export ZIP은
  사용자가 고른 위치에 plaintext로 저장하며, cloud-mounted 폴더를 고른 경우 동기화는
  macOS/해당 제공자가 수행하고 KaosCal은 이를 Cloud 기능으로 관리하지 않음

상세 범위와 제외 범위는 [v1-scope.md](docs/v1-scope.md)를, 결정 근거는 [ADR](docs/adr/README.md)을 확인한다.

## 사용자 안내

설치·첫 실행·권한·주요 기능과 로컬 데이터 관리는 [User Guide](docs/user-guide.md),
현재 제한과 우회 방법은 [Known Issues](docs/known-issues.md)를 따른다. 데이터 처리와
보안 보고 경계는 [Privacy](PRIVACY.md)와 [Security](SECURITY.md)에 정리한다.
외부 beta 라이선스는 아직 승인되지 않았으며 [Beta License Placeholder](BETA-LICENSE.md)가
필수 결정과 배포 중단선을 기록한다.

## 개발 시작 전 준비

전체 Xcode와 테스트 전용 Exchange 캘린더가 필요하다. 자격 증명이나 실제 회사 일정을 공유하지 않는다. 자세한 준비물은 [developer-setup.md](docs/developer-setup.md)에 있다.

## 빌드와 테스트

```sh
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO test
```

## GitHub Actions 자동 빌드·DMG 배포

`main`/`master` push와 pull request에서는 [`ci.yml`](.github/workflows/ci.yml)이 최신
검증 러너의 전체 test·50% app line coverage 하한·static analyzer·unsigned Release build와
최소 지원 macOS 14의 전체 test를 실행한다. 성공한 `.app` zip과 `.xcresult`는 Actions
artifact로 7일/14일 동안 보관한다. GitHub 저장소의 **Actions** 탭에서 해당 실행과
artifact를 확인할 수 있다.

`v0.1.0`처럼 세 자리 버전 태그를 push하면
[`release.yml`](.github/workflows/release.yml)이 전체 test, Apple Silicon/Intel 공용 Release
build, ad-hoc signing, DMG·checksum 검증을 수행하고 GitHub prerelease에 두 파일을 올린다.

```sh
git tag v0.1.0
git push origin v0.1.0
```

자동 artifact는 `KaosCal-0.1.0-local.dmg`와 `SHA256SUMS.txt`다. 이 경로는 현재
Developer ID 인증서를 사용하지 않는 로컬 테스트 전달용이며, 외부 beta 배포 판정을
대체하지 않는다. 정식 배포는 [Release Runbook](docs/release-runbook.md)의 Developer ID
서명·notarization·stapling gate를 별도로 통과해야 한다.

## 자동업데이트

앱에는 Sparkle 2 기반 자동업데이트 수신기가 포함된다. 유효한 HTTPS appcast URL과
32-byte Ed25519 공개 키가 build에 함께 들어간 경우에만 updater가 시작되며, 구성된 빌드는
정기 확인·자동 설치와 앱 메뉴의 `Check for Updates…`를 제공한다. 값이 없는 일반 개발
빌드는 기존 기능을 그대로 실행하고 업데이트 메뉴만 비활성화한다.

로컬 `.env`에는 공개 값만 다음 형식으로 넣을 수 있다. xcconfig에서 `//`가 주석으로
해석되지 않도록 URL의 두 slash 사이에 `$()`를 사용한다.

```xcconfig
KAOSCAL_UPDATE_FEED_URL = https:/$()/updates.example.com/kaoscal/appcast.xml
KAOSCAL_SPARKLE_PUBLIC_ED_KEY = <Sparkle generate_keys가 출력한 공개 키>
```

Sparkle private key는 `.env`나 저장소에 넣지 않는다. 현재 GitHub prerelease의 ad-hoc
`*-local.dmg`는 자동업데이트 원본이 아니다. 실제 update 발행은 Developer ID 서명,
notarization, signed appcast와 이전 build upgrade smoke를 모두 요구하며 자세한 절차는
[Release Runbook](docs/release-runbook.md), 결정 경계는
[ADR-020](docs/adr/ADR-020-signed-automatic-updates.md)을 따른다.
현재 origin 저장소는 private이므로 인증 없는 Sparkle client가 raw/release URL을 feed로
사용할 수 없다. GitHub token을 앱에 넣지 말고, 발행 시 별도 정적 HTTPS endpoint를 정한다.

EventKit 수동 QA에는 Calendar entitlement가 포함된 서명 앱이 필요하므로 `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES`로 로컬 서명 빌드를 만든다. 실제 검증 명령과 결과는 [implementation-log.md](docs/implementation-log.md)에 남긴다.

첫 실행에서는 앱 안의 `Allow Full Calendar Access`를 누른 뒤 macOS 권한 창에서 허용한다. 사용자가 권한을 허용했다고 보고했더라도 실행 중인 최신 서명 앱에 `Full calendar access`가 표시되는지 별도로 확인한다. 계정 비밀번호나 MFA 코드는 KaosCal에 입력하지 않는다. toolbar의 `Reload events`는 macOS EventKit의 현재 로컬 데이터를 다시 읽을 뿐 Exchange 원격 동기화를 강제하지 않는다.

환경변수에 Exchange 계정, 비밀번호, MFA, OAuth token을 넣지 않는다. 앱은 macOS Internet Accounts에 이미 로그인된 계정을 EventKit으로 사용한다. 로컬 Context DB는 앱 sandbox의 Application Support 아래 자동 생성된다.

## 문서 운영

사용자에게 보이는 동작, 데이터 모델, 지원 범위가 바뀌면 같은 변경에서 ADR, v1 범위,
QA 기준과 구현 로그를 함께 갱신한다. 현재 단계·최신 test count·열린 gate의 요약 판정은
[Current Status](docs/current-status.md)를 기준으로 하고, exact artifact와 실행 증거는 QA,
Implementation Log와 Exchange Compatibility에 보존한다. 상세 규칙은
[ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 정의한다.
