# KaosCal 사용자 가이드

> 기준 구현: 2026-07-25, Tasks 통합 관리·planning·Calendar 결합과 signed updater
>
> 이 문서는 현재 저장소의 코드와 승인된 설계 문서를 기준으로 한다. KaosCal은 아직
> 외부 베타 배포 준비 단계이며, 공개 다운로드 위치·최종 설치 패키지·일반 지원 창구는
> 확정되지 않았다. 자동업데이트 코드는 준비됐지만 서명된 feed가 없는 개발 빌드에서는
> 비활성 상태다.

## 1. 설치와 사전 준비

KaosCal은 macOS Calendar에 이미 연결된 일정을 보여 주고, 사용자가 승인한 변경을
EventKit을 통해 저장한다. KaosCal 안에서 Exchange, iCloud 또는 다른 캘린더 계정에
로그인하지 않는다.

- 최소 운영체제는 macOS 14다. 현재 검증은 Apple Silicon을 우선한다.
- 사용할 계정과 캘린더를 먼저 macOS의 Internet Accounts 및 Calendar.app에서
  구성하고 동기화한다.
- 계정 비밀번호, MFA 코드, tenant/client secret 또는 OAuth token을 KaosCal에
  입력하지 않는다.
- 현재 저장소에는 공용 notarized 설치 파일과 실제 업데이트 feed가 확정되어 있지 않다.
  테스터는 빌드를 전달한 사람에게서 받은 신뢰 가능한 서명 빌드와 그 빌드에 포함된
  설치 안내만 사용한다. 출처를 확인할 수 없는 앱을 실행하거나 Gatekeeper 경고를
  임의로 우회하지 않는다.
- 소스에서 직접 빌드하는 개발자는 [저장소 README](../README.md)와
  [개발 환경 안내](developer-setup.md)를 따른다. 개발용 ad-hoc 서명 빌드는 공개
  배포 빌드가 아니다.

### 업데이트

- 승인된 signed feed가 포함된 빌드는 백그라운드에서 새 버전을 정기 확인하고 자동으로
  내려받아 설치할 수 있다. 앱 메뉴의 `Check for Updates…`로 즉시 확인할 수도 있다.
- 메뉴가 비활성화되어 있으면 현재 빌드에 feed URL 또는 공개 서명 키가 없는 것이다.
  앱을 다시 설치하거나 Gatekeeper를 우회하지 말고 빌드를 전달한 사람에게 확인한다.
- 업데이트 확인 실패는 일정과 로컬 데이터 사용을 막지 않는다. 반복 실패 시 출처가
  확인된 새 빌드를 받기 전까지 현재 버전을 계속 사용할 수 있다.
- 업데이트 때문에 Event Brief, task, backup이나 Calendar 원본을 삭제하지 않는다. 설치
  뒤 version/build와 기존 데이터가 그대로 열리는지 확인한다.

## 2. 첫 실행과 캘린더 권한

1. KaosCal을 실행한다.
2. `Allow Full Calendar Access`를 선택한다.
3. macOS 권한 창에서 전체 캘린더 접근을 허용한다. KaosCal은 Day, Week, Agenda에
   일정을 표시하고 사용자가 요청한 원본 변경을 저장하기 위해 읽기·쓰기 가능한 전체
   접근이 필요하다. `Write Only` 권한만으로는 동작하지 않는다.
4. 앱으로 돌아오면 권한과 일정을 다시 확인한다. 필요하면 도구 막대의
   `Reload events`를 누른다.

`Reload events`는 macOS EventKit이 현재 가지고 있는 데이터를 다시 읽을 뿐,
Exchange나 다른 제공자에 원격 동기화를 강제하지 않는다. 일정이 보이지 않으면 먼저
Calendar.app에서 계정과 동기화 상태를 확인한다.

### 권한을 거부했거나 나중에 취소한 경우

- 앱의 `Open System Settings`를 선택하거나 macOS **System Settings > Privacy &
  Security > Calendars**에서 KaosCal의 전체 접근을 허용한다.
- KaosCal로 돌아와 `Reload events` 또는 `Try Again`을 선택한다.
- 조직 정책으로 권한이 `Restricted` 상태이면 KaosCal에서 이를 우회할 수 없다.
- 권한을 다시 주어도 일정이 없으면 Calendar.app에서 해당 계정이 활성화되어 있는지
  확인한다.

첫 실행에는 KaosCal이 Calendar password/MFA를 받지 않는다는 점, Event Brief의 local
저장과 plaintext backup 경계를 설명하는 안내가 먼저 표시된다. `Continue to Calendar
Access` 뒤 위 권한 절차를 진행한다.

KaosCal 로컬 데이터베이스를 열지 못한 경우 앱은 in-memory 저장소로 대체하지 않고
전용 `Local data needs recovery` 화면을 표시한다. 직접 만든 current-schema KaosCal
backup이 있으면 `Restore From Backup…`을 선택한다. archive가 완전히 검증되기 전에는
기존 DB를 건드리지 않고, 성공 경로에서도 기존 SQLite와 sidecar를 `Recovery` 폴더에
보존한다. 호환 backup이 없다면 임의 파일 교체나 schema downgrade 대신 아래의
[데이터 위치](#8-데이터-위치와-앱-제거)를 참고해 전체 폴더를 보존한다.

## 3. 화면과 이동

왼쪽에는 mini month, 화면 선택, Calendar Set, 캘린더 목록이 있다. 가운데는 선택한
Day, Week, Agenda 또는 Task Center이고, 오른쪽 inspector에는 선택한 일정의 출처,
권한, 중복 후보와 Event Brief가 표시된다.

- `⌘1` Day, `⌘2` Week, `⌘3` Agenda, `⌘4` Tasks
- `⌘T` 오늘로 이동
- `⌘N` 새 일정
- `⌘R` 현재 일정 또는 Tasks 다시 읽기
- mini month의 날짜를 선택하거나 도구 막대의 이전·다음·Today 버튼으로 기간 이동
- mini month의 날짜 아래 점은 현재 Enabled 캘린더와 선택한 Calendar Set에서 그날 겹치는
  일정이 하나 이상 있음을 뜻함. 여러 일정이어도 점은 하나이며 VoiceOver는 개수를 읽음
- `Reload events`는 일정, Tasks 화면의 `Reload tasks`는 로컬 할 일 목록을 다시 읽음

## 4. 일정과 Event Brief 사용하기

### 일정 보기·만들기·편집하기

Day, Week 또는 Agenda에서 일정을 선택하면 오른쪽 inspector에 캘린더, source,
KaosCal role, 편집 가능 상태가 나타난다.

- 새 일정은 도구 막대의 `New event` 또는 `⌘N`으로 만든다.
- 편집 가능한 일정은 inspector의 `Edit Original Event`에서 제목, 대상 캘린더,
  위치, 시간/종일 상태, floating 또는 IANA 시간대, 원본 일정 notes를 바꿀 수 있다.
- 새 일정은 표현 가능한 기본 일·주·월·년 반복 규칙을 설정할 수 있다.
- 반복 일정을 편집할 때는 `This event` 또는 지원되는 경우 `This and future` 범위를
  먼저 고르고, 영향 미리보기를 확인한 뒤 최종 승인한다.
- 캘린더 이동이나 시간 의미 변경처럼 연결된 Event Brief에 영향을 주는 변경은 별도
  review 후에만 저장된다.

편집기의 `Original event notes`는 Calendar.app 원본에 속하며 캘린더 제공자에
동기화될 수 있다. 오른쪽 Event Brief의 `Notes`와 Before/During/After 작업은
KaosCal 로컬 데이터이며 원본 event notes에 기록되지 않는다.

초대 일정, 참석자가 있는 회의, 구독/생일 캘린더와 macOS가 read-only로 보고한
캘린더는 원본 편집이 제한된다. 이 경우 inspector에 이유가 표시되며 Event Brief는
계속 로컬에서 편집할 수 있다. RSVP, 참석자 및 주최자 관리는 Calendar.app에서 한다.

### Event Brief와 Task Center

선택한 일정의 Event Brief에서 다음 항목을 관리할 수 있다.

- Before, During, After 작업의 추가·이름 변경·이동·완료·삭제
- KaosCal 로컬 notes
- 일정이 끝난 뒤에도 남는 After 후속 작업

notes는 잠시 후 자동 저장된다. `Not saved`가 나타나면 내용을 보존한 채 `Retry`를
사용한다. 저장 실패 상태에서는 backup/import/reset이 시작되지 않는다.

Task Center에는 일정에 연결된 작업과 일정 없이 만드는 Personal task가 함께
표시된다.

- `Today`: 오늘 기한인 미완료 작업
- `Upcoming`: 내일 이후 기한 작업
- `Overdue`: 오늘보다 이전 기한인 미완료 작업
- `No Date`: 기한이 없는 미완료 작업
- `After Review`: 종료된 일정의 미완료 After 작업
- `Completed`: 완료된 event/personal 작업

Personal task는 항상 KaosCal 로컬에만 저장된다. Event Brief 작업은 해당 calendar에
Task Provider destination을 설정한 경우 Apple Reminders, Google Tasks, Todoist 또는
Microsoft To Do의 선택 list/project로 연결될 수 있다. Task Center는 아직 Event Brief에
연결되지 않은 provider task도 같은 날짜 filter와 검색에 함께 표시한다. provider·계정·list와
Linked/Syncing/Needs attention 상태를 표시한다. missing은 다시 확인하거나 local 작업으로
remote를 재생성할 수 있고, conflict는 remote 또는 local 버전을 명시적으로 선택한다.

오른쪽 inspector의 이름은 `Tasks`다. 처음 열었는데 Reminders 권한이 아직 결정되지
않았다면 macOS 권한 창이 바로 열린다. 허용하면 기존 Apple Reminders 목록과 task가
표시되고, task가 없어도 상단의 초록 연결 표시가 보인다. 이전에 거부했다면
`Open System Settings`로 Reminders 권한을 허용한 뒤 Tasks의 새로고침을 사용한다.

`All Lists`를 누르면 현재 읽을 수 있는 목록을 Apple Reminders, Google Tasks, Todoist와 Microsoft To Do
source별로 나눠 보여 준다. 각 항목에는 list 이름, account와 불러온 전체 task 수가 표시된다.
특정 list를 선택하면 다른 list의 작업은 숨기고 그 list만 평면 목록으로 표시한다.
선택한 list가 계정에서 삭제되면 다음 authoritative reload 뒤 `All Lists`로 돌아간다.
선택한 list, 완료 상태와 정렬은 Details로 갔다 돌아오거나 앱을 다시 열어도 복원된다.
검색어는 다시 열 때 초기화된다.

- `Open`, `Completed`, `All`: 완료 상태 필터
- `Search tasks`: 제목과 설명을 즉시 검색
- `Due date`, `Priority`, `Title`: 현재 결과의 정렬 기준
- `All Lists`: source·account·list section으로 다시 표시

Todoist의 `Completed`는 provider archive를 bounded 조회해 최근 90일 완료 작업을 보여 준다.
그보다 오래된 Todoist 완료 이력을 전체 로컬 기록처럼 약속하지 않는다.

writable provider 항목은 체크 원을 눌러 바로 완료하거나 미완료로 바꿀 수 있다. 행을 누르면
목록 아래의 크기 조절 가능한 상세 drawer가 열리고 최신 원격 내용을 다시 읽은 뒤 제목,
notes, 기한과 완료 상태를 수정한다. 다른 행을 누르면 drawer를 유지한 채 해당 작업으로
전환하며, 저장하지 않은 변경이 있으면 drawer 안에서 계속 편집하거나 버릴 수 있다. Apple
Reminders, Microsoft To Do와 Todoist는 priority도 편집할 수 있고 Google Tasks의 due는
날짜만 저장된다. Microsoft To Do는 due와 별도로 reminder 시각을 켜거나 끌 수 있으며 알림
전달은 Microsoft To Do의 알림 설정을 따른다. Apple Reminders는 writable list 사이 이동도
지원하며 Todoist는 같은 account 안에서 project/section 사이를 이동할 수 있다. 상단 `+`도
같은 drawer를 열어 선택한 writable provider list/project에 새 task를 만든다. `All Lists`에서는
destination을 먼저 고른다. drawer 위 경계를 끌어 목록과 상세 영역의 높이를 조절하고,
`Esc`나 닫기 버튼으로 상세 편집을 닫는다.

상단 선택 아이콘을 누르면 여러 작업을 고르는 모드가 열린다. 이 모드에서는 선택한 writable
작업을 한 번에 완료·미완료로 바꿀 수 있다. 목록 이동은 Apple Reminders와 Todoist처럼
provider가 안전한 move를 지원하는 동일 provider/account 작업에만 나타난다. Apple Reminders만
서로 다른 Apple account 사이 이동을 허용한다. read-only 작업이
섞이면 일괄 write를 실행하지 않는다. 행의 버튼은 Tab으로 이동하고
Return/Space로 실행하며 포커스된 작업은 위·아래 방향키로 옮길 수 있다.

생성·수정·완료·이동·삭제가 성공하면 Tasks 안에 `Undo`가 나타난다. Undo는 현재 앱 실행 중
마지막 변경에만 적용되며, 그 뒤 원본 provider에서 작업이 바뀌었다면 conflict로 중단하고
덮어쓰지 않는다. 삭제 Undo는 같은 내용의 새 provider task를 만들기 때문에 원격 ID는
달라질 수 있지만 연결된 KaosCal Event Task는 새 ID에 다시 연결된다.

삭제 확인에는 task 이름과 provider·account·list가 표시된다. 연결된 Event Task의 원격
Reminder를 삭제해도 KaosCal의 로컬 task는 삭제되지 않고 `Needs attention`으로 남는다.
저장 전에 Reminders.app에서 같은 task가 바뀌었으면 draft를 자동 덮어쓰지 않는다.
`Reload Latest`로 원격 최신본을 불러오거나 `Cancel`로 닫는다. 권한 철회나 목록 오류에는
새로고침 또는 Reminders 개인정보 설정 이동을 사용한다. Microsoft To Do/Todoist가 신뢰할
수 있는 원본 URL을 제공한 행에는 원본 열기 아이콘이 나타난다. 특정 Apple
Reminder를 여는 신뢰할 수 있는 EventKit URL은 제공하지 않는다.

Task Center의 깃발/별/슬라이더에서는 local Event/Personal task의 priority, 중요 표시,
반복 간격, 예상 시간, 실제 수행 timer와 checklist를 관리한다. 반복 task를 완료하면 다음
occurrence가 로컬에 생성되고 checklist는 미완료로 복사되며 실제 시간은 0부터 시작한다.
이 planning metadata는 이 Mac의 KaosCal DB에만 저장되며 provider가 지원하지 않는 필드로
조용히 전송되지 않는다. `Task views`에서 role·날짜 filter·grouping·검색을 이름 붙여 저장할 수 있다.

오른쪽 provider task를 캘린더 시간 칸으로 끌면 15분 단위, 기본 1시간의 일정 block과 During
Event Task를 만들고 원본 task를 연결한다. Event Brief에서는 기존 provider task 연결과
Before/During/After task의 fixed 또는 event start/end 상대 기한을 설정할 수 있다. 현재
Calendar Set 관련 task만 보고 싶으면 오른쪽 Tasks의 해당 toggle을 켠다.

Event Brief task를 Reminders에 생성·수정하려면 Settings의
`Task Providers > Calendar Destinations`에서 해당 calendar의 destination list도 선택한다.

### 원본 삭제와 연결 복구

원본 일정 삭제와 로컬 Event Brief 삭제는 서로 다른 동작이다.

- 연결된 원본을 KaosCal에서 삭제할 때는 notes/tasks/history 영향을 먼저 보여 주고
  별도 최종 확인을 요구한다. 지원되는 삭제가 성공하면 원본에는 Undo가 없고, 로컬
  Brief는 보존된다.
- 원본을 찾지 못한 첫 확인만으로 Brief를 삭제하지 않는다. 별도의 `Check Again` 뒤
  `Keep as Orphan`, 정확한 일정으로 `Relink`, `Delete Local Brief`를 선택할 수 있다.
- `Delete Local Brief`는 해당 KaosCal notes/tasks/link/history를 삭제하지만
  Calendar.app 또는 Exchange 원본을 삭제하지 않는다.
- 반복 series의 정확한 occurrence를 안전하게 판정할 수 없으면 자동 연결 대신 사용자가
  정확한 occurrence를 직접 선택해야 한다.

## 5. Calendar role과 Calendar Set

각 캘린더 행의 메뉴에서 `Work`, `Personal`, `Family`, `Shared`, `Subscription`,
`Other` role을 지정할 수 있다.

- 사용자가 지정한 role은 KaosCal 로컬 DB에만 저장된다. Calendar.app의 이름, 색상,
  공유 설정 또는 계정 데이터는 바꾸지 않는다.
- subscribed/birthdays 캘린더는 현재 source 정보가 있을 때 `Subscription`으로
  추론하고, 그 밖의 캘린더는 사용자가 정하기 전 `Other`로 둔다.
- Sidebar의 `Calendar Set`에는 모든 enabled calendar를 보여 주는 `All Calendars`,
  role을 기준으로 계산하는 `Smart Role Filters`, 사용자가 저장한 정확한 calendar
  조합이 따로 표시된다. 선택한 항목은 로컬 DB에 저장되어 재실행 뒤 복원된다.
- **Settings > Calendar Sets**에서 `+`로 이름 있는 Set을 만들고, rename/delete/reorder,
  account별 `Include All`/`Remove All` 또는 calendar별 checkbox로 membership을 바꾼다.
  새 Set은 현재 enabled calendar로 시작하거나 의도적으로 비워 둘 수 있다. 한 calendar는
  여러 Set에 들어갈 수 있고 서로 다른 role의 calendar도 같은 Set에 함께 넣을 수 있다.
- **Settings > Calendars**의 `Enabled`는 모든 Set에 적용하는 master display 설정이다.
  calendar를 disable하면 All, Smart Filter와 saved Set에서 숨지만 저장된 membership은
  삭제되지 않는다. `Block`은 표시/Set과 독립이므로 숨긴 calendar도 busy time을 막을 수 있다.
- membership은 EventKit calendar identifier의 exact match로만 자동 복원한다. Set에
  들어 있던 calendar가 사라지면 `Unavailable Calendars`에 snapshot 이름을 남기고
  이름만 같은 calendar로 자동 연결하지 않는다. 사용자가 `Replace…`로 새 calendar를
  고르거나 `Remove`를 눌러야 membership이 바뀐다. 권한 거부·로딩·조회 실패 중에는
  missing으로 단정하지 않고, 권한 있는 calendar 조회가 완료된 뒤에만 unavailable을 표시한다.
- Set 전환은 Day/Week/Agenda 표시만 좁히고 raw Calendar fetch, Event Brief 연결·복구,
  duplicate review와 editor destination을 삭제하거나 제한하지 않는다. 숨겨진 duplicate·
  relink 대상 또는 원본 저장 뒤 focus할 일정이 현재 filter 밖이면 active Set을 바꾸지 않는
  temporary reveal을 사용하고, 이미 보이는 일정에는 임시 상태를 만들지 않는다.

## 6. Possible duplicate 이해하기

KaosCal은 서로 다른 캘린더에 있는 일정 중 제목이 정규화 후 같고 다음 시간 조건을
만족하면 `Possible duplicate` 후보로 표시한다.

- 시간 일정: 시작과 종료가 각각 15분 이내
- 종일 일정: 같은 날짜 범위

이 표시는 검토 후보일 뿐 중복 확정이 아니다. KaosCal은 후보를 자동으로 merge,
hide 또는 delete하지 않는다. 후보를 선택하면 해당 일정으로 이동할 뿐 원본을
변경하지 않는다.

## 7. Backup, import, reset

macOS의 KaosCal 앱 메뉴에서 **Settings > Local Data**를 연다. 이 화면의 모든 작업은
KaosCal 로컬 SQLite만 대상으로 하며 Calendar.app 또는 Exchange 원본을 만들거나
수정하거나 삭제하지 않는다.

이 기능은 자동 test와 signed Release의 화면·file panel·typed `RESET` 활성화까지
검증됐지만, 현재 exact Release에서 실제 export 파일 작성, 선택한 backup import와 reset
mutation은 아직 manual pending이다. 외부 beta gate가 닫히기 전에는 비민감 테스트 데이터와
전용 test user에서만 아래 절차를 사용하고, 중요한 유일 사본의 복구 수단으로 의존하지 않는다.

### 수동 backup

1. `Export Backup…`을 선택한다.
2. 저장 위치와 `.zip` 파일명을 고른다.
3. 완료 메시지와 경로를 확인한다.

ZIP에는 정확히 `manifest.json`과 `kaoscal.sqlite`가 들어 있다. KaosCal은 ZIP과
SQLite를 애플리케이션 수준에서 암호화하거나 서명하지 않는다. notes/tasks, 일정
제목·시간·위치·identifier, 변경 snapshot과 원본 event notes snapshot이 plaintext로
포함될 수 있다. 신뢰하는 로컬·외장 위치에 보관하고, cloud 폴더를 선택했다면 해당
cloud 제공자의 동기화·공유 정책도 적용됨을 고려한다.

수동 export는 요청할 때만 실행된다. 현재 버전에는 예약 backup, 보관 기간/개수 설정,
자동 pruning이 없다.

### Import

1. `Import Backup…`에서 직접 만든 신뢰 가능한 KaosCal ZIP을 선택한다.
2. `Replace Local Data` 확인을 승인한다.
3. 완료 메시지에 표시된 pre-import recovery backup 경로를 기록한다.

Import는 record merge가 아니라 현재 KaosCal 로컬 DB 전체 교체다. archive 구조,
manifest, byte count/SHA-256, 현재 migration/schema, SQLite integrity와 foreign key를
검증한 뒤 실행하며, 먼저 현재 DB의 recovery ZIP을 만든다. SHA-256은 ZIP 내부 byte
무결성 확인값이지 제작자를 인증하는 서명이 아니다. ZIP을 풀어 일반 압축 도구로 다시
만든 파일, 다른 schema의 과거/미래 backup 또는 출처를 모르는 backup은 사용하지
않는다.

### Reset Local Data

1. `Reset Local Data…`를 선택한다.
2. 확인란에 정확히 `RESET`을 입력한다.
3. `Delete Local Data`를 선택하고 recovery backup 경로를 기록한다.

Reset은 Event Brief, event link/task, Personal task, local change history, calendar
role/usage preference, saved Calendar Set·membership·선택과 provider/reference local row를
비운다. 실행 전 자동 recovery ZIP을 만들며 이 생성이 실패하면 reset하지 않는다.
Calendar/Exchange 일정과 DB schema/migration history는 삭제하지 않는다.

Import/reset 전 자동 recovery ZIP은 active DB 옆의 `Backups` 폴더에 남는다.
KaosCal은 이를 자동 삭제하지 않으므로 사용자가 보관 공간과 수명을 관리해야 한다.
restore/reset과 rollback까지 실패하면 그 session의 로컬 변경과 캘린더 변경을
잠그고 앱 종료를 요구한다. 메시지에 나온 `Backups` 폴더를 보존하고 임의 재시도를
하지 않는다.

더 자세한 archive 계약은 [Backup, Restore, and Local Reset](backup-restore.md)을
참고한다.

## 8. 데이터 위치와 앱 제거

현재 production 앱은 App Sandbox 안의 user Application Support에
`KaosCal/kaoscal.sqlite`를 만든다. bundle identifier가 현재 값인 일반적인 경로는
다음과 같지만, 빌드와 실행 환경에 따라 container 경로가 달라질 수 있다.

```text
~/Library/Containers/com.adtstack.kaoscal/Data/Library/Application Support/KaosCal/
├─ kaoscal.sqlite
└─ Backups/
```

항상 **Settings > Local Data > Storage**에 표시되는 실제 경로를 기준으로 하고,
`Show in Finder`로 확인한다. 수동 export ZIP은 사용자가 선택한 위치에 있다.

앱을 제거하려면 다음 경계를 먼저 확인한다.

1. 필요한 Event Brief와 task가 있으면 수동 backup을 만든다.
2. KaosCal 로컬 데이터를 지우려면 가능할 때 먼저 `Reset Local Data`를 사용한다.
3. KaosCal을 종료한 뒤 앱을 제거한다.
4. 완전한 로컬 제거가 필요하면 Settings에서 확인해 둔 `KaosCal` Application Support
   폴더와 그 안의 `Backups`를 별도로 삭제한다. 다른 앱 또는 Calendar 계정 폴더는
   삭제하지 않는다.
5. 사용자가 내보낸 ZIP, 외장 디스크 복사본과 cloud 사본은 각 위치에서 별도로
   삭제한다.
6. 필요하면 System Settings의 Calendars 개인정보 설정에서 KaosCal 권한을 취소한다.

앱 번들 또는 KaosCal 로컬 DB를 제거해도 Calendar/Exchange 원본 일정은 삭제되지
않는다. 반대로 KaosCal에서 만들어 수정한 원본 일정은 캘린더 계정에 남는다.

## 9. 현재 제한과 지원 경계

현재 구현에서 다음 기능은 제공하지 않거나 지원 범위를 제한한다.

- KaosCal 계정, KaosCal Cloud, 모바일 앱, 직접 Microsoft Graph/EWS/CalDAV sync
- AI/LLM/ML 기반 생성·요약·분류·추천·검색·자동 스케줄링·자동 이동·자동 수락·자동 삭제
- 초대 RSVP, 참석자/주최자 관리, 참석자가 있는 meeting 원본 편집
- 프로젝트·팀 작업·Kanban, Personal task의 provider sync와 legacy Exchange Tasks sync.
  Event Brief task와 오른쪽의 일반 provider task만 Apple Reminders, Google Tasks, Todoist,
  Microsoft To Do에 직접 연결할 수 있다.
- 복잡한 반복 규칙의 강제 변환, linked `This and future`, 일반적인 반복/delete Undo,
  앱 재실행 뒤 Undo
- Calendar Set의 cloud/device sync·시간/위치 자동 전환, role별 색/이름 override,
  duplicate 자동 정리
- backup record merge, 예약 backup, 자동 retention/pruning
- schema가 다른 backup migration/downgrade, 임의 SQLite 복구와 backup 없는 bootstrap reset
- exact Release에서 실제 export 파일 작성·backup import·reset mutation의 live gate
- signed appcast를 사용한 이전 build → 새 build 자동 설치·재실행의 end-to-end gate

알림·일정 검색·전체 Month부터 시작하는 후속 기능 순서와 현재 상용 기능 격차는
[상용 기능 로드맵](commercial-feature-roadmap.md)을 따른다.

KaosCal 고유의 notes, task, history, Calendar Set과 설정은 이 Mac에만 저장된다. Calendar는
macOS EventKit, 연결한 Event Brief task는 이 Mac과 사용자가 선택한 provider 사이에서
직접 동기화되며 KaosCal 계정·중계 서버·Cloud를 사용하지 않는다. 자세한 영구 경계는
[ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md)를 따른다.

Exchange 관련 지원 문구는 macOS Calendar에 구성된 Exchange Online 캘린더로
한정한다. 온프레미스 Exchange는 검증 전까지 지원을 약속하지 않는다. 또한 현재
자동 테스트가 통과했더라도 Calendar.app 시각 round-trip, live all-day/time-zone,
반복 future split, 실제 calendar move, shared read-only 같은 항목은 독립 수동 gate가
남아 있다. 중요한 업무 캘린더에 적용하기 전에 별도 테스트 캘린더와 비민감 fixture로
동작을 확인한다.

일반 지원 이메일이나 form은 아직 지정되지 않았다. 테스터는 빌드를 전달받은 기존
비공개 채널을 사용하되, 비밀번호·MFA·token·실제 notes/tasks·원본 backup DB를 보내지
않는다. 보안 문제는 [SECURITY.md](../SECURITY.md)의 임시 신고 절차와 금지 항목을
따른다. 데이터 처리 경계는 [PRIVACY.md](../PRIVACY.md)를 참고한다.
