# KaosCal 사용자 가이드

> 기준 구현: 2026-07-12, Phase 10
>
> 이 문서는 현재 저장소의 코드와 승인된 설계 문서를 기준으로 한다. KaosCal은 아직
> 외부 베타 배포 준비 단계이며, 공개 다운로드 위치·최종 설치 패키지·자동 업데이트·
> 일반 지원 창구는 확정되지 않았다.

## 1. 설치와 사전 준비

KaosCal은 macOS Calendar에 이미 연결된 일정을 보여 주고, 사용자가 승인한 변경을
EventKit을 통해 저장한다. KaosCal 안에서 Exchange, iCloud 또는 다른 캘린더 계정에
로그인하지 않는다.

- 최소 운영체제는 macOS 14다. 현재 검증은 Apple Silicon을 우선한다.
- 사용할 계정과 캘린더를 먼저 macOS의 Internet Accounts 및 Calendar.app에서
  구성하고 동기화한다.
- 계정 비밀번호, MFA 코드, tenant/client secret 또는 OAuth token을 KaosCal에
  입력하지 않는다.
- 현재 저장소에는 공용 notarized 설치 파일과 업데이트 경로가 확정되어 있지 않다.
  테스터는 빌드를 전달한 사람에게서 받은 신뢰 가능한 서명 빌드와 그 빌드에 포함된
  설치 안내만 사용한다. 출처를 확인할 수 없는 앱을 실행하거나 Gatekeeper 경고를
  임의로 우회하지 않는다.
- 소스에서 직접 빌드하는 개발자는 [저장소 README](../README.md)와
  [개발 환경 안내](developer-setup.md)를 따른다. 개발용 ad-hoc 서명 빌드는 공개
  배포 빌드가 아니다.

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

- `Today`: 오늘까지의 미완료 작업과 날짜 없는 Personal task
- `Upcoming`: 미래 기한 작업
- `After Review`: 종료된 일정의 미완료 After 작업
- `Completed`: 완료된 event/personal 작업

Personal task와 Event Brief 작업은 Apple Reminders, Exchange Tasks 또는 KaosCal
서버로 동기화되지 않는다.

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
- `Calendar Set`의 `All Calendars` 또는 role 필터는 Day/Week/Agenda에 보이는 일정을
  좁힌다. 현재 버전에는 임의 이름의 saved set이나 캘린더별 visibility 저장 기능이
  없다.

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

Reset은 Event Brief, event link/task, Personal task, local change history와 calendar
role preference의 active row를 비운다. 실행 전 자동 recovery ZIP을 만들며 이 생성이
실패하면 reset하지 않는다. Calendar/Exchange 일정과 DB schema/migration history는
삭제하지 않는다.

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
- AI 자동 스케줄링·자동 이동·자동 수락·자동 삭제
- 초대 RSVP, 참석자/주최자 관리, 참석자가 있는 meeting 원본 편집
- 프로젝트·팀 작업·Kanban, Apple Reminders/Exchange Tasks 동기화
- 복잡한 반복 규칙의 강제 변환, linked `This and future`, 일반적인 반복/delete Undo,
  앱 재실행 뒤 Undo
- custom saved Calendar Set, role별 색/이름 override, duplicate 자동 정리
- backup record merge, 예약 backup, 자동 retention/pruning
- schema가 다른 backup migration/downgrade, 임의 SQLite 복구와 backup 없는 bootstrap reset
- exact Release에서 실제 export 파일 작성·backup import·reset mutation의 live gate

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
