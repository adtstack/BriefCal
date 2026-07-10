# Implementation Log

이 문서는 실제로 한 작업과 검증 결과를 시간순으로 남긴다. 계획만 적지 않고, 명령·테스트·수동 검증의 성공 또는 실패를 모두 기록한다.

## 기록 규칙

- 코드 또는 사용자에게 보이는 동작을 바꾸면 같은 변경에서 항목을 추가한다.
- 각 항목에는 날짜, 관련 ADR, 변경 파일, 검증, 남은 위험을 적는다.
- 검증하지 못한 내용은 `미검증`으로 명시한다. 추측을 통과로 기록하지 않는다.

## 2026-07-10 — 문서 기준선 복원 및 v1 결정 정리

- 관련 ADR: ADR-001, ADR-002, ADR-003, ADR-004, ADR-005
- 변경: 원격 `origin/main`의 기존 문서 기준선을 로컬 `main`에 복원하고, v1 범위·Exchange 호환성·개발 준비·ADR 구조를 추가했다.
- 보존: 기존 `.gitignore`의 사용자 변경은 유지했다.
- 검증:
  - `git status --short --branch`에서 `main...origin/main`과 기존 `.gitignore` 변경을 확인했다.
  - `docs/` 10개 초기 문서가 작업 폴더에 복원된 것을 확인했다.
  - `git diff --check`가 통과해 문서 변경에 whitespace 오류가 없음을 확인했다.
  - Xcode 앱이 설치되어 있지 않아 앱 빌드·EventKit 실계정 검증은 **미검증**이다.
- 남은 위험: Exchange Online의 실제 권한·공유·반복·시간대 동작, EventKit ID 재연결, 배포 서명.

## 2026-07-10 — 개발 및 Exchange 테스트 환경 준비 확인

- 관련 ADR: ADR-001
- 확인:
  - Xcode 26.6 / Build 17F113이 설치되어 있다.
  - 사용자가 macOS 인터넷 계정에서 Exchange 계정 로그인과 Calendar 동기화를 완료했다.
  - 수정 가능한 테스트 calendar 이름은 `KAOS-TEST`다.
  - 사용자는 앱의 full calendar access 요청을 허용할 예정이다.
  - Exchange Online 또는 온프레미스 여부는 **미확인**으로 유지한다.
- 보안: 비밀번호, MFA 코드, OAuth token, client secret은 필요하지 않으며 저장하지 않는다.
- 결과: Phase 0 앱 bootstrap을 시작할 수 있다.
- 남은 위험: read-only 공유 calendar 미준비, Exchange backend 종류 미확인.

## 2026-07-10 — Phase 0 네이티브 앱 bootstrap 완료

- 관련 ADR: ADR-002, ADR-005, ADR-006
- 변경 파일:
  - `KaosCal.xcodeproj`와 shared `KaosCal` scheme
  - `KaosCal/App`, `Features/CalendarShell`, `DesignSystem`, `Resources`
  - `KaosCalTests/AppStateTests.swift`
  - Xcode/Swift build artifact용 `.gitignore`
- 동작:
  - BusyCal의 정보 밀도만 참고한 독자적인 3-pane shell
  - Day/Week/Agenda/Tasks navigation과 `Command-1`~`Command-4`
  - Day/Week all-day lane 및 시간 grid placeholder
  - Agenda, Task Center, Event Brief empty state
  - Phase 1 전에는 permission을 요청하거나 `KAOS-TEST`를 runtime에 하드코딩하지 않음
- 빌드 기준:
  - Xcode 26.6 / Swift compiler 6.3.3 / Swift language mode 5
  - macOS 14.0+, bundle identifier `com.adtstack.kaoscal`
  - App Sandbox + Calendar entitlement + full-access usage description
- 검증:
  - `plutil -lint` project/Info.plist/entitlement: pass
  - unsigned Debug build: pass
  - XCTest: 5 tests, 0 failures
  - ad-hoc signed Debug build: pass
  - `codesign --verify --deep --strict`: pass
  - sandbox/calendar/get-task-allow entitlement 확인: pass
  - built Info.plist full-access usage description 확인: pass
  - 실행 프로세스와 `KaosCal` window 생성 확인: pass
- 제약:
  - 데스크톱 접근성 검증용 `orca` CLI가 설치되어 있지 않아 pixel-level/AX-tree 검사는 수행하지 못했다.
  - Phase 0 shell은 실제 EventKit 데이터가 아닌 disconnected/empty state만 표시한다.
- 결과: Phase 0 완료. 다음 단계는 Phase 1 EventKit full access와 Exchange calendar/event read-only 조회다.

## 다음 항목 템플릿

```markdown
## YYYY-MM-DD — 작업 제목

- 관련 ADR:
- 변경 파일:
- 검증:
- 결과: pass / fail / blocked
- 남은 위험:
```
