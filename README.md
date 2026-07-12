# KaosCal

KaosCal은 macOS Calendar에 이미 연결된 일정을 읽고 편집하면서, 각 일정의 준비물·메모·후속 작업을 로컬에 보존하는 macOS 앱이다.

현재 상태: **Phase 8 Multi-Calendar Clarity 구현·자동·signed Release·운영 DB v3 migration checkpoint 완료 / 실화면·shared read-only Exchange gate 대기**. Day/Week/Agenda, Sidebar, Inspector, 원본 editor와 Task Center에 `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other` 역할과 source/account/permission을 일관되게 표시한다. `All`과 역할별 virtual Calendar Set, invitation·attendee·subscription·birthdays·provider read-only의 typed reason, 다른 calendar의 정규화 제목과 보수적 시간 범위를 비교하는 비파괴 `Possible duplicate` review를 제공한다. 역할 변경과 Set/duplicate projection은 EventKit 원본을 바꾸지 않으며 custom saved Set·자동 merge/hide/delete는 범위 밖이다.

최종 suite는 **199 tests executed, 198 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**다. 결과 bundle은 `/private/tmp/KaosCalPhase8FinalTests-20260712-1415.xcresult`다. ad-hoc Release `/private/tmp/KaosCalPhase8FinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6c595445dadfb60588410329222557d00865c222`는 strict codesign, hardened runtime, sandbox·Calendar entitlement, XCTest/get-task-allow 부재를 통과했다. exact Release 정상 부팅으로 sandbox 운영 DB에 sparse `v3_calendar_clarity`를 적용했고, 최종 rebuild도 다시 정상 기동·종료해 integrity/FK와 기존 v1/v2 table 내용 hash가 유지되며 새 `calendar_preferences`가 0행인 것을 확인한 뒤 process 0으로 종료했다. 화면 잠금 때문에 긴 source/고밀도 card/VoiceOver와 shared read-only Exchange 설명은 직접 보지 못했으므로 자동·Release 통과와 live UI 통과를 구분한다.

역사적 live 증거는 분리 유지한다. 2026-07-11 run `20260711-1626-B7D2`에서 full access, `KAOS-TEST`·`일정` writable Exchange 표시와 `KAOS-TEST` 비반복 create→restart/refetch→update→delete·서버 residue 0을 확인했다. 2026-07-12 Phase 7C run `20260712-025027-KST`에서는 linked 비반복 원본의 final delete 1회, Calendar.app·Outlook 제거와 local Brief/Notes/Before·During·After task 보존을 확인했다. 반복 `thisEvent`, all-day, floating/zoned, calendar move, 외부 삭제 동기화 지연과 shared read-only Viewer는 별도 gate이며, 참석자가 있는 meeting과 초대 원본 편집은 v1에서 Calendar.app 전용이다.

## 제품 범위

- macOS 14 이상
- macOS Calendar에 구성된 Exchange 캘린더를 우선 검증 대상으로 하는 EventKit 앱
- Day, Week, Agenda 캘린더, Sidebar mini month와 Task Center
- 종일 일정, 시간대, 반복 일정의 안전한 표시·편집
- Event Brief와 KaosCal 작업은 로컬 SQLite에만 저장

상세 범위와 제외 범위는 [v1-scope.md](docs/v1-scope.md)를, 결정 근거는 [ADR](docs/adr/README.md)을 확인한다.

## 시작 전 준비

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

사용자에게 보이는 동작, 데이터 모델, 지원 범위가 바뀌면 같은 변경에서 ADR, v1 범위, QA 기준, 구현 로그를 함께 갱신한다. 이 규칙은 [ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 정의한다.
