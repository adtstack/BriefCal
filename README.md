# KaosCal

KaosCal은 macOS Calendar에 이미 연결된 일정을 읽고 편집하면서, 각 일정의 준비물·메모·후속 작업을 로컬에 보존하는 macOS 앱이다.

현재 상태: **Phase 6 반복·safe-move·change-log·session Undo 구현 / 비반복 EventKit live gate 부분 통과 / 반복·이동 live gate 대기**. Day/Week/Agenda, Event Brief, Task Center와 Phase 5의 시간 안전 원본 편집 위에 명시적 `이번 일정`/`이번 이후` 범위, 기본 반복 규칙, 영향 확인 후 write, linked calendar safe move, additive `event_change_log`, 좁은 세션 Undo를 연결했다. Phase 6의 **121-test checkpoint**와 122-test read-only gate를 보존하면서 현재 suite는 **132 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**이며, 테스트와 live QA 전후에 운영 Context DB가 바뀌지 않았다. 최신 build-only ad-hoc signed Release는 CDHash `511a11258d95a49c826b49dc463a79039707807e`로 strict codesign·hardened runtime·sandbox·Calendar entitlement 검증을 통과했다.

2026-07-11 live FinalRelease EventKit run `20260711-1626-B7D2`는 recurrence-fix artifact CDHash `63ded03a9d704976c4ba45340f2748eda9892382`에서 수행했고, 위 최신 CDHash는 후속 build-only checkpoint다. live run에서는 `Full calendar access`, writable Exchange 캘린더 `KAOS-TEST`와 `일정`을 확인했다. `KAOS-TEST`에 만든 비반복 fixture는 Outlook 서버에서 `singleInstance`이고 recurrence가 없었으며, 앱 재실행·refetch 뒤에도 반복 badge나 scope 선택 없이 단일 일정으로 수정·삭제됐다. 수정 뒤에도 서버 recurrence는 없었고, 최종 source/destination marker residue는 `0/0`이다. 이 과정에서 EventKit이 비반복 일정에도 `occurrenceDate == startDate`를 줄 수 있음을 발견해 반복 소속 판정을 `hasRecurrenceRules || isDetached`로 고정하고 비반복 `occurrenceDate`는 `nil`로 정규화했다. 이전 Outlook connector run `20260711-1512-7C4E`의 독립 writable fixture·제한된 반복·시간대·cleanup 결과도 역사적 checkpoint로 유지한다. 다만 Calendar.app 시각 round-trip, live all-day, 반복 `이번 일정`/`이번 이후`, 실제 calendar move는 아직 검증하지 않았고, 이 결과만으로 Exchange Online 전체 지원을 선언하지 않는다. linked 삭제·orphan 처리는 Phase 7 범위이고, 참석자가 있는 meeting과 초대 원본 편집은 v1에서 Calendar.app 전용이다.

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
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KaosCal.xcodeproj -scheme KaosCal -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/KaosCalDerivedData -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=NO test
```

EventKit 수동 QA에는 Calendar entitlement가 포함된 서명 앱이 필요하므로 `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES`로 로컬 서명 빌드를 만든다. 실제 검증 명령과 결과는 [implementation-log.md](docs/implementation-log.md)에 남긴다.

첫 실행에서는 앱 안의 `Allow Full Calendar Access`를 누른 뒤 macOS 권한 창에서 허용한다. 사용자가 권한을 허용했다고 보고했더라도 실행 중인 최신 서명 앱에 `Full calendar access`가 표시되는지 별도로 확인한다. 계정 비밀번호나 MFA 코드는 KaosCal에 입력하지 않는다. toolbar의 `Reload events`는 macOS EventKit의 현재 로컬 데이터를 다시 읽을 뿐 Exchange 원격 동기화를 강제하지 않는다.

환경변수에 Exchange 계정, 비밀번호, MFA, OAuth token을 넣지 않는다. 앱은 macOS Internet Accounts에 이미 로그인된 계정을 EventKit으로 사용한다. 로컬 Context DB는 앱 sandbox의 Application Support 아래 자동 생성된다.

## 문서 운영

사용자에게 보이는 동작, 데이터 모델, 지원 범위가 바뀌면 같은 변경에서 ADR, v1 범위, QA 기준, 구현 로그를 함께 갱신한다. 이 규칙은 [ADR-005](docs/adr/ADR-005-decision-and-change-recording.md)에 정의한다.
