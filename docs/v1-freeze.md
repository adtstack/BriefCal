# v1 동결 결정

> 상태: Accepted
> 결정일: 2026-07-13
> 적용 대상: KaosCal v1 범위와 현재 구현 기준선

## 1. 결정

KaosCal v1은 현재 저장소 상태를 기준으로 기능 개발을 종료하고 동결한다. 이후의
새로운 외부 task provider, 직접 Calendar API, 동기화 기능은 v1 기능으로 추가하지
않고 v2 실행계획으로 분리한다.

v1 동결은 “모든 수동 gate가 통과했다”는 뜻이 아니다. 실제 Exchange 반복·종일·시간대
검증, VoiceOver, 손상 DB 복구와 Developer ID 배포가 남아 있다는 사실을 보존한 채,
그 항목을 v1의 미완성 기능으로 계속 확장하지 않겠다는 제품 결정이다.

정본 문서는 다음 순서로 해석한다.

1. [v1 범위](v1-scope.md)
2. [현재 상태](current-status.md)
3. 이 동결 결정문
4. [통합 캘린더·Task 로드맵](integrated-calendar-task-roadmap.md)
5. [v2 실행계획](v2-execution-plan.md)

## 2. 동결되는 v1 제공 범위

- macOS 14+ 네이티브 Calendar/EventKit 기반 Day, Week, Agenda
- local Event Brief와 Before/During/After Task Center
- 비반복 원본 일정 CRUD와 제한된 반복·시간대·종일 안전 처리
- linked event의 impact 확인, missing/orphan/relink, 원본 삭제 후 local 보존
- multi-calendar role, virtual set, typed read-only 설명, duplicate 후보 표시
- local SQLite context store, 수동 export/import/reset, recovery backup
- onboarding, 권한 복구 안내, ad-hoc Release checkpoint와 운영 문서

v1은 원본 Calendar의 notes를 KaosCal notes로 사용하지 않으며, task를 Apple Reminders,
Google Tasks, Todoist, Microsoft To Do로 자동 동기화하지 않는다.

## 3. 동결 후에도 유지할 수 있는 변경

다음은 v1 기능 확장이 아니라 유지보수로 간주한다.

- 빌드가 깨지는 컴파일·서명·설치 회귀 수정
- 데이터 손실, 원본 일정 오염, 보안·권한 경계 위반 수정
- 명백한 crash, migration 손상, 백업 복구 안전성 결함 수정
- 문서의 오탈자·실행 명령·현재 상태 증거 갱신
- 이미 동결된 기능의 접근성 또는 사용자에게 보이는 명백한 회귀 수정

이 범위를 넘어서는 변경은 v2 작업으로 기록하고 v1 기준선에 병합하지 않는다.

## 4. v1 기준선 보존 절차

동결을 저장소의 재현 가능한 기준선으로 만들 때 다음을 순서대로 수행한다.

1. 작업 트리의 Phase 10 코드·문서 변경을 검토하고 의도하지 않은 파일을 분리한다.
2. Debug 전체 테스트, Release build, codesign 검사를 다시 실행하고 정확한 명령과 결과를
   `implementation-log.md`에 남긴다.
3. v1 기준선 commit을 만든다. 태그 이름은 `v1-frozen` 또는 실제 배포 버전과 충돌하지
   않는 저장소 규칙을 따라 결정한다.
4. 소스 archive, `Package.resolved`, test result bundle, Release audit, 현재 문서와
   알려진 제한을 함께 보존한다.
5. v1이 다음 단계로 다시 열리지 않도록 issue·PR 라벨에 `v1-maintenance`와 `v2`를
   구분한다.

현재 작업 트리에 남아 있는 변경을 자동으로 commit하거나 태그하지 않는다. 위 절차는
동결을 실제 release 기준선으로 보존할 때 수행하는 운영 작업이다.

## 5. 알려진 제한의 처리

다음 항목은 실패한 v1 기능을 계속 보수하는 backlog가 아니라, v1의 명시적 제한이다.

- 실제 Exchange의 recurring `thisEvent`, future split, calendar move
- all-day와 floating/zoned time의 전체 실계정 round-trip
- shared read-only Exchange fixture
- 최종 Release의 실제 VoiceOver·keyboard·고밀도 화면 검증
- 실제 손상 sandbox DB와 power-loss/rollback fault 복구
- Developer ID, notarization, stapling, clean-user beta 설치

사용자에게 영향을 주는 데이터 손실·보안 결함이 발견되면 v1 유지보수 예외로 즉시
처리한다. 사용성 개선이나 새 provider 요구는 v2 문서에서 우선순위를 다시 정한다.

## 6. v2로 넘어가는 기준

v2 구현은 v1 저장 모델을 폐기하는 작업으로 시작하지 않는다. 먼저 local-only task가
그대로 동작하는 provider abstraction을 만들고, 외부 provider는 additive migration과
명시적 연결 상태로 추가한다. OAuth token은 Keychain에만 두며 기존 backup 계약을
확장할 때도 token과 원격 원문을 archive에 넣지 않는다.

v2의 첫 개발 문서는 [v2 실행계획](v2-execution-plan.md)과 [T0 Provider abstraction]
(v2/phase-t0-provider-abstraction.md)이다.
