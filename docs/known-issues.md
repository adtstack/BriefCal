# Known Issues and Current Limits

> 마지막 갱신: 2026-07-17
>
> 이 문서는 현재 코드와 검증 기록에서 확인된 사용자 관점의 제한만 다룬다. 구현됐지만 live 검증이 끝나지 않은 항목과 의도적으로 지원하지 않는 항목을 구분한다.

## 설치·권한·동기화

### v2 Apple Reminders 연동은 아직 live fixture 전이다

v2 Phase 1에는 Reminders 권한 요청, writable list destination, event task의 생성·수정·완료·삭제
및 외부 변경 projection이 구현되어 있다. 그러나 현재 자동 테스트는 실제 iCloud/On My Mac
Reminders 계정과 권한 철회를 검증하지 않았으므로 beta-ready로 판정하지 않는다. Personal task는
이번 단계에서 의도적으로 local-only다. Task Center의 provider/account/list badge와
missing 재확인·local 기준 remote 재생성, conflict의 local/remote 선택, disconnected 설정 복구는
자동 fixture에서 구현·검증됐다. 오른쪽 `Tasks` 첫 진입의 Reminders 권한 요청, 거부 시
System Settings 복구, 전체 높이와 연결 완료 표시는 구현·자동 검증됐지만 실제 TCC prompt와
iCloud/On My Mac 목록 표시는 아직 수동 gate다. Apple/Microsoft list 선택과 account/source
구분, Open/Completed/All·검색·정렬은 fake provider와 300/360pt offscreen에서 검증했지만
실계정 menu·keyboard·VoiceOver는 아직 수동 gate다. 다른 remote task를 provider/account/list
source와 함께 직접 고르는 relink와 원격 task를 지우지 않는 durable task별 local-only unlink는
2026-07-17 코드에 구현됐다. 다만 새 회귀 테스트는 컴파일만 했고 실제 Apple/Google/Todoist/
Microsoft 계정의 재실행·충돌·삭제·retry limit까지는 아직 실행 검증하지 않았다.

pending create는 원격 성공과 local binding 저장 사이에 프로세스가 종료되면 원격 ID를 알 수
없다. 자동 무한 재시도는 하지 않으며, 재실행 뒤 exact remote relink 또는 local-only 선택으로
복구해야 한다. Microsoft task 설명은 개인정보 경계를 위해 SQLite/backup에 저장하지 않으므로
재실행 뒤 첫 full delta가 끝나기 전에는 설명이 잠시 비어 있을 수 있다.

**현재 권장:** Reminders destination을 설정하기 전 v1 local-only task 흐름을 사용하고, live
검증 전에는 중요한 원격 task를 단독 정본으로 두지 않는다.

### 외부 배포용 build가 아직 없다

현재 Release checkpoint는 로컬 ad-hoc 서명 검증용이다. Developer ID 서명,
notarization, stapling과 clean-user 설치를 마친 공개 beta package가 아니다.

**현재 권장:** 개발 환경 밖 사용자에게 이 artifact를 배포하지 않는다.

### Calendar full access가 필요하다

권한을 거부하거나 철회하면 KaosCal은 Calendar 일정과 기존 화면 선택을 메모리에서
제거하고 원본 일정 기능을 사용할 수 없다. 로컬 Event Brief DB를 삭제하지는 않는다.

**우회:** 앱의 `Open System Settings` 안내로 권한을 허용한 뒤 KaosCal로 돌아와
새로고침한다. 이 거부→복구 경로는 자동 검증됐지만 실제 최신 Release UI 수동 gate는
남아 있다.

### `Reload events`는 서버 동기화 버튼이 아니다

새로고침은 macOS EventKit이 현재 보유한 데이터를 다시 읽는다. Exchange 서버와의
원격 동기화는 macOS Calendar가 담당하며 KaosCal이 강제하지 않는다.

**우회:** 서버 변경이 바로 보이지 않으면 Calendar.app에서 동기화 상태를 먼저
확인한 뒤 KaosCal을 새로고침한다.

### 지원 계정 경계

KaosCal은 macOS Calendar에 이미 구성된 계정을 EventKit으로 사용한다. Microsoft
계정 비밀번호, MFA나 OAuth token을 KaosCal에 입력하는 방식은 제공하지 않는다.
온프레미스 Exchange와 shared read-only Exchange의 실제 호환성은 아직 통과 선언하지
않았다.

## 일정 편집

### 초대 일정과 참석자가 있는 meeting은 원본 편집 불가

이 일정들은 표시하고 local Event Brief와 작업을 붙일 수 있지만 RSVP, 참석자,
주최자, 원본 제목·시간·삭제 변경은 지원하지 않는다.

**우회:** 원본 변경은 Calendar.app에서 수행한다. local Event Brief는 계속 편집할 수
있다.

### read-only·구독·생일 캘린더는 원본 편집 불가

KaosCal이 read-only로 판정한 원본은 저장·이동·삭제할 수 없다. shared calendar의
구체 ACL 원인은 EventKit이 제공한 범위 이상으로 추측해 표시하지 않는다.

**우회:** 권한이 있는 Calendar.app 또는 캘린더 소유자 쪽에서 원본을 변경한다.
KaosCal의 local Event Brief는 원본 권한과 별도로 편집할 수 있다.

### Calendar role·saved Set은 로컬이며 새 live 검증이 남아 있다

Work/Personal 같은 role, role별 Smart Role Filter, calendar별 Enabled/Block과 사용자
이름의 saved Set은 KaosCal의 로컬 SQLite에만 적용된다. Calendar.app의 캘린더 이름·색·
공유 권한을 바꾸거나 다른 Mac/iPhone으로 동기화하지 않는다. saved Set은 exact calendar
identifier membership을 사용하므로 계정 재추가 등으로 identifier가 바뀌면 unavailable로
남고, 같은 이름의 calendar에 자동 연결하지 않는다. `Replace…` 또는 `Remove`를 사용자가
명시해야 한다. CRUD·겹치는 Set·혼합 role·missing rebind와 후속 AppState review 수정의
최종 자동/offscreen gate는 통과했지만 실계정/실창/VoiceOver gate는 아직 완료 판정 전이다.
possible duplicate는 검토 후보일 뿐
자동으로 병합·숨김·삭제하지 않는다.

**현재 권장:** 중요한 Set은 재실행 뒤 membership을 확인한다. unavailable 항목은 source와
calendar를 확인한 뒤에만 Replace한다. 원본 캘린더 설정과 실제 중복 일정 정리는
Calendar.app에서 수행한다.

### 복잡한 반복 변경은 제한된다

KaosCal이 손실 없이 표현할 수 없는 여러 규칙과 복잡한 서버 반복 규칙은 보존한다.
선택 occurrence의 일반 필드는 안전한 `이번 일정` 경로에서만 다룰 수 있고, 복잡한
규칙의 `이번 이후`와 규칙 자체 변경은 지원하지 않는다. Event Brief가 연결된 반복
일정의 `이번 이후` 변경·삭제도 여러 local context를 안전하게 재연결할 수 없어
사전에 차단한다.

**우회:** 해당 변경은 Calendar.app에서 수행한다. 중요한 반복 변경 뒤에는 KaosCal의
각 occurrence와 Event Brief 연결을 확인한다.

### 반복·all-day·시간대·calendar 이동의 live 범위가 아직 제한적이다

비반복 단일 일정 CRUD와 비반복 linked 원본 삭제는 실제 Exchange 경로를 통과했다.
반면 recurring `thisEvent`, 지원 범위 내 future split, all-day, floating/zoned time과
linked calendar move는 최신 live gate를 완료하지 않았다.

**현재 권장:** 중요한 일정에서는 Calendar.app을 사용하고, KaosCal에서 변경했다면
Calendar.app의 날짜·시간·반복 범위를 확인한다. 이는 확인된 실패가 아니라 미완료
검증 항목이다.

### 외부에서 삭제한 반복 occurrence는 자동 판정되지 않을 수 있다

살아 있는 반복 series의 한 occurrence 삭제와 검색 범위 밖으로 이동한 detached
occurrence를 안전하게 구분할 수 없는 경우 KaosCal은 자동으로 orphan 처리하지 않는다.

**우회:** recovery 화면에서 정확한 occurrence를 수동으로 확인해 relink한다. 후보가
불명확하면 자동 연결하지 않는다.

### Undo는 일반 복원 기능이 아니다

Undo는 같은 실행 세션에서 마지막으로 성공한, strong identity가 있는 linked 비반복
단일 calendar/time 변경 한 건에만 제공될 수 있다. 앱 재실행, 후속 성공 write,
반복 일정, detached occurrence와 삭제에는 제공되지 않는다.

**우회:** Undo가 없거나 stale 확인에서 차단되면 Calendar.app에서 현재 원본을 확인해
수정한다.

### 원본 저장과 local Brief 갱신 사이에 부분 성공이 가능하다

Calendar 원본과 KaosCal local DB는 하나의 원자적 저장으로 묶이지 않는다. 원본 변경은
성공했지만 local 재연결·기록이 실패하면 앱은 같은 작업을 자동 재시도하거나 원본을
자동 복원하지 않는다.

**우회:** 오류가 “재시도하지 말고 Calendar.app에서 확인”을 안내하면 같은 버튼을
반복해서 누르지 말고 Calendar.app의 원본과 KaosCal의 보존된 Brief를 각각 확인한다.

## Local Data·백업

### backup은 plaintext이며 서명되지 않는다

ZIP에는 Event Brief notes/tasks, personal task, linked 일정의 제목·시간·위치·식별
metadata, change snapshot의 원본 notes, calendar role·usage와 saved Set 이름·membership·
현재 선택이 포함될 수 있다. 본문은
검사하거나 가리지 않는다. KaosCal은 ZIP/SQLite를 암호화하거나 제작자 서명하지
않으며 SHA-256은 파일 일치 확인일 뿐 출처 인증이 아니다.

**현재 권장:** 직접 만든 backup만 신뢰하고 암호화된 디스크 등 신뢰하는 위치에
보관한다. notes/tasks에 입력한 민감정보도 그대로 포함될 수 있다고 가정한다.

### Import는 병합이 아니라 전체 local DB 교체다

현재 실행 앱과 application identifier, schema와 migration 목록이 정확히 같은
backup만 가져올 수 있다. 과거 schema 자동 migration, 미래 schema downgrade와
record 단위 병합은 제공하지 않는다.

**안전 경계:** import 전에 현재 local DB의 recovery ZIP을 만든다. preflight가
실패하면 active DB를 바꾸지 않는다. 가져오기 전 확인 화면에서 교체 범위를 검토한다.

### 정기 backup과 자동 보관 정리가 없다

Backup은 사용자가 요청하는 수동 export만 제공한다. Import/reset 전 recovery ZIP은
자동으로 만들지만 schedule backup은 아니며, Application Support의 `Backups`에 남은
파일도 기간, 개수나 저장 공간 기준으로 자동 삭제되지 않는다. 실패 시 새 ZIP 경로가
항상 오류 문구에 표시되는 것도 아니다.

**우회:** Settings의 active DB 위치에 인접한 `Backups` 폴더를 정기적으로 확인하고,
필요한 파일을 별도 보관한 뒤 사용자가 직접 정리한다.

### 손상 DB bootstrap 복구는 same-schema KaosCal backup이 필요하다

Phase 10은 DB open/migration 실패 화면에서 strict KaosCal ZIP을 선택하는 복구 UI를
제공한다. 현재 앱과 exact migration/schema가 같은 backup만 허용하며, 과거 schema 자동
migration, 미래 schema downgrade, 임의 SQLite 선택, record merge와 backup 없는 새 DB
초기화는 제공하지 않는다.

**안전 경계:** 유효한 backup을 고르기 전 기존 DB 파일군은 건드리지 않는다. 복구 시
기존 DB와 sidecar는 `Recovery`에 함께 보존되며 자동 삭제되지 않는다. 자동 회귀는
격리·복원·rollback을 통과했지만 실제 signed Release 손상 DB/file-panel 복구와 crash/
power-loss window는 manual pending이다.

### Reset Local Data는 Calendar 일정 삭제가 아니다

Reset은 Event Brief, event/personal task, provider/reference row, link/change history,
calendar role·usage와 saved Set·membership·selection 같은 KaosCal local data를 비운다.
Calendar.app·Exchange 원본 일정은 만들거나 수정하거나 삭제하지 않는다. 반대로 local
Brief 삭제도 원본 일정을 삭제하지 않는다.

**주의:** 원본과 local data를 모두 지우려면 각각의 명시적 삭제 흐름을 별도로
실행해야 한다. Reset 전 recovery ZIP 생성이 실패하면 Reset도 시작하지 않는다.

### Personal task는 다른 task 서비스와 동기화되지 않는다

Personal task는 KaosCal local DB에만 저장된다. Event Brief의 event task는 calendar별
Task Provider destination이 설정된 경우에만 지원 provider로 연결된다. 이 연동은 현재
자동 fixture를 통과했지만 실제 계정·권한 철회·충돌·cleanup live gate 전이다. Exchange
Tasks와 다른 기기의 KaosCal로 직접 동기화하는 기능은 없다.

**현재 권장:** live gate 전에는 중요한 원격 task를 KaosCal 연결 task 하나에만 의존하지
않는다. 여러 기기에서 보여야 하는 Personal task는 해당 서비스에 별도로 기록한다.

## 화면·수동 검증 상태

Phase 8의 긴 source/role/restriction 문구, saved Calendar Set Settings/Sidebar,
고밀도 card와 VoiceOver는 자동 또는
offscreen checkpoint만 통과했다. Phase 9의 실제 Settings scroll, Open/Save panel과
typed Reset activation은 run `20260712-1616-KST`에서 통과했지만, 파일 작성·backup을
선택한 import·reset mutation, signed Release의 failed-bootstrap file-panel 복구와 실제
rollback fault는 실행하지 않았다. 온보딩과 recovery 화면은 offscreen bitmap까지만
검증했으며 VoiceOver·keyboard 실제 창 검증은 남아 있다. Tasks의 list/source 필터와
읽기 계층은 300×600·360×700 fixture bitmap에서 통과했지만 실제 Apple/Microsoft 데이터의
긴 list/account 이름, menu focus, Increase Contrast와 VoiceOver는 남아 있다.

이 제한의 최신 판정과 남은 gate는 [Current Status](current-status.md), 상세 복구 계약은
[Backup, Restore, and Local Reset](backup-restore.md), 사용자별 검증 절차는
[QA checklist](qa-checklist.md)를 따른다.
