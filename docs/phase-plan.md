# Phase Plan

## 진행 원칙

KaosCal은 한 번에 한 phase씩 구현한다.
각 phase는 사용 가능한 작은 데모 단위로 끝나야 하며, 앱은 항상 빌드 가능한 상태여야 한다.

## Phase 표

| Phase | 목표 | 핵심 산출물 | 통과 기준 |
| --- | --- | --- | --- |
| 0 | Repo bootstrap | Xcode project, README, architecture skeleton | 앱이 빌드되고 빈 shell이 뜬다. |
| 1 | EventKit read-only | EventKitProvider, permission flow, events list | 시스템 캘린더 일정이 Agenda에 표시된다. |
| 2 | Calendar UI shell | 3-pane layout, Week view, event cards | 일정을 클릭하면 inspector가 열린다. |
| 3 | Local context DB | GRDB migrations, repositories, tests | Event Brief가 SQLite에 저장/조회된다. |
| 4 | Event Brief UX | Before/During/After panel, inline editing | 일정마다 체크리스트를 붙이고 완료할 수 있다. |
| 5 | Real event editing | create/update/delete/move | KaosCal에서 만든 일정이 Calendar.app에도 보인다. |
| 6 | Change-safe move | Move confirmation, change log | 이동 후 context가 유지되고 로그가 남는다. |
| 7 | Lifecycle / After Review | completed/orphaned/after task handling | 종료된 일정의 후속 작업을 처리할 수 있다. |
| 8 | Multi-calendar clarity | source badge, role, read-only explanation | 일정 출처와 권한이 명확히 표시된다. |
| 9 | Backup / settings | export/import, reset local data | DB 백업과 복구가 된다. |
| 10 | Paid beta polish | onboarding, QA, distribution notes | 외부 베타 사용자에게 배포 가능하다. |

## Phase 0: Repo Bootstrap

작업:
- 새 macOS SwiftUI 프로젝트 생성
- 기본 window, sidebar, toolbar shell 생성
- README, docs, ADR 폴더 생성
- 최소 formatting 규칙 결정

Definition of Done:
- Xcode에서 빌드 성공
- 앱 실행 시 KaosCal shell 표시
- README에 제품 원칙과 실행 방법 존재

## Phase 1: EventKit Read-Only

작업:
- Calendar permission request 구현
- EventKitProvider 작성
- 오늘 기준 -30일 ~ +90일 이벤트 fetch
- 캘린더 목록과 이벤트 목록 표시

Definition of Done:
- 권한 허용 시 실제 macOS Calendar 이벤트 표시
- 권한 거부 시 복구 안내 표시
- 읽기 전용 캘린더와 writable 캘린더 구분

## Phase 2: Calendar UI Shell

작업:
- 3-pane layout 구현
- Week view grid 구현
- Agenda list 구현
- event card 디자인 적용
- 선택 이벤트 state 연결

Definition of Done:
- 일정 클릭 시 오른쪽 패널에 기본 정보 표시
- Today 버튼과 이전/다음 기간 이동 동작
- 고밀도에서도 겹침과 클리핑 없음

## Phase 3: Local Context DB

작업:
- GRDB 설치
- Database bootstrap
- migrations 작성
- EventContextRepository 테스트
- Event identity fingerprint 생성

Definition of Done:
- 앱 재실행 후 Event Brief 유지
- 원본 이벤트 notes에 아무것도 쓰지 않음
- Repository tests 통과

## Phase 4: Event Brief UX

작업:
- 오른쪽 패널을 Event Brief 중심으로 재구성
- Before/During/After 섹션 추가
- 체크리스트 CRUD
- notes inline edit
- 빈 상태와 템플릿 버튼

Definition of Done:
- 일정별 체크리스트 저장
- 완료 체크 상태 저장
- 일정 선택 전환 시 올바른 Brief 로드

## Phase 5: Real Event Editing

작업:
- 새 일정 생성 popover
- 기본 편집: title/time/calendar/location/notes
- edit form 또는 drag로 일정 시간 변경
- 삭제 구현

Definition of Done:
- 생성한 일정이 Calendar.app에 보임
- 수정/삭제가 EventKit에 반영됨
- read-only 일정은 편집 UI 비활성화

## Phase 6: Change-Safe Move

작업:
- 일정 이동 감지
- Move confirmation UI
- 연결 항목 리스트 표시
- change log 기록
- undo 최소 구현

Definition of Done:
- 이동 전/후 시간이 로그에 남음
- context_id 유지
- 취소 시 EventKit과 local DB 모두 변경되지 않음

## Phase 7: Lifecycle / After Review

작업:
- scheduled/moved/completed/cancelled/orphaned 상태 구현
- 일정 종료 후 After Review 표시
- 후속 작업만 오늘 목록에 남기기
- 원본 일정 삭제 감지 시 orphaned 표시

Definition of Done:
- 종료된 일정의 After task 처리 가능
- 삭제된 원본 일정의 Brief가 보관됨
- 사용자가 보관/재연결/삭제 선택 가능

## Phase 8: Multi-Calendar Clarity

작업:
- calendar role 설정
- source badge 표시
- read-only reason 표시
- calendar sets 초안
- 중복 후보 감지 초안

Definition of Done:
- 각 일정이 Work/Personal/Subscription 등 역할을 표시
- 읽기 전용 일정은 왜 수정 불가인지 설명
- 비슷한 시간/제목의 후보 감지

## Phase 9: Backup / Settings

작업:
- DB export/import
- reset local context
- 저장 위치 표시
- privacy copy 작성
- manual backup UX

Definition of Done:
- zip export 생성
- 새 DB에 import 성공
- 원본 캘린더 이벤트 삭제 없이 KaosCal 데이터만 삭제 가능

## Phase 10: Paid Beta Polish

작업:
- 온보딩 polish
- crash-safe error states
- keyboard shortcuts
- empty states
- direct distribution 준비
- license placeholder

Definition of Done:
- 외부 테스트 사용자가 설명 없이 설치, 실행, 권한 허용, 핵심 데모를 수행할 수 있음

## 작업 프로토콜

모든 phase 작업은 아래 순서를 따른다.

1. 기존 파일을 먼저 읽는다.
2. 목표 범위를 한 문장으로 고정한다.
3. 가장 작은 유용한 변경을 구현한다.
4. 가능한 빌드 또는 테스트를 실행한다.
5. 로직 변경에는 테스트를 붙인다.
6. 아키텍처나 동작이 바뀌면 docs를 업데이트한다.
7. 변경 파일과 검증 결과를 요약한다.
8. 다음 phase 또는 다음 작업 하나만 제안한다.

