# ADR-006: 네이티브 프로젝트·빌드·보안 기준

> 상태: Accepted
> 날짜: 2026-07-10
> Phase 9 확장: ADR-015가 명시적 backup Open/Save panel용 user-selected read/write entitlement를 추가함

## 배경

Phase 0에는 실제 macOS `.app` metadata, entitlement, shared scheme, 단위 테스트가 필요하다. 현재 환경에는 XcodeGen, Tuist, Homebrew가 없으므로 외부 project generator에 의존할 수 없다.

## 결정

- Xcode 26.6에서 열 수 있는 checked-in `BriefCal.xcodeproj`와 shared `BriefCal` scheme을 사용한다.
- 호환성이 높은 명시적 `PBXGroup`/`PBXFileReference` 구조와 project object version 56을 사용한다.
- 최소 OS는 macOS 14.0, 언어 모드는 Swift 5, 설치된 Swift 6.3.3 compiler를 사용한다.
- 앱과 hosted XCTest 단위 테스트 target을 둔다. 외부 SPM dependency는 Phase 3 GRDB 도입 전까지 추가하지 않는다.
- provisional bundle identifier는 `com.adtstack.briefcal`이다. 배포용 identifier가 바뀌면 Calendar TCC 권한을 다시 받아야 한다.
- App Sandbox와 Calendar entitlement를 켜고, full-access usage description을 명시한다. Phase 9부터 사용자가 명시적으로 고른 backup ZIP을 읽고 쓰는 범위에만 `com.apple.security.files.user-selected.read-write`를 추가한다. 자동 recovery backup은 app container의 Application Support에 남긴다.
- Exchange 동기화는 macOS/EventKit이 담당하므로 network client entitlement를 추가하지 않는다.
- Phase 0 UI는 permission을 요청하지 않는다. Phase 1의 설명 화면 뒤에서 사용자가 명시적으로 요청한다.

## 검증 기준

- `plutil -lint`가 project, Info.plist, entitlement에서 통과한다.
- Debug build와 단위 테스트가 통과한다.
- ad-hoc signed Debug app이 codesign strict verification을 통과한다.
- built Info.plist에 `NSCalendarsFullAccessUsageDescription`이 존재한다.
- signed app에 sandbox/calendar/user-selected read-write entitlement가 포함되고 `get-task-allow`은 Release에 포함되지 않는다.
- 앱 프로세스와 `BriefCal` window가 생성된다.

## 결과

Phase 1부터 bundle identifier와 Calendar entitlement를 유지해 실제 EventKit 권한을 검증했다. Phase 9은 EventKit 권한을 바꾸지 않고 user-selected backup 파일에만 적용되는 read/write entitlement를 ADR-015에 따라 확장했다. Developer ID와 Team은 외부 beta 배포 단계에서 결정한다.
