# QA Checklist

## QA 목표

KaosCal QA의 핵심은 예쁜 캘린더가 뜨는지보다 "사용자의 일정 맥락을 잃지 않는지"를 확인하는 것이다.
특히 Event Brief 데이터가 원본 calendar notes를 오염시키지 않는지, 일정 이동과 삭제에서 context가 살아남는지 반복 검증한다.

## 테스트 환경

최소 환경:
- 깨끗한 macOS 사용자 계정
- macOS Calendar에 등록된 테스트 전용 Exchange Online 계정
- 수정 가능한 Exchange calendar와 공유 read-only Exchange calendar
- 네트워크가 꺼진 상태
- 권한을 거부한 상태
- 앱 재설치 또는 DB 초기화 상태

## 수동 테스트 시나리오

### 1. 첫 실행과 full access 허용

절차:
1. 앱을 처음 실행한다.
2. 캘린더 권한 요청을 허용한다.
3. Agenda와 실제 Day/Week event card를 각각 확인한다.

기대 결과:
- 실제 Exchange Calendar 일정이 표시된다.
- 캘린더 목록이 표시된다.
- 앱이 로컬 저장 정책을 명확히 설명한다.
- `KAOS-TEST`가 `Exchange`로 표시되고 lock이 없으면 writable로 판정한다.
- `KAOS-TEST`의 EventKit calendar color가 sidebar와 event rail에 일관되게 표시된다.
- Exchange source 표시는 backend가 Exchange Online이라는 증거로 사용하지 않는다.
- `Reload events`는 EventKit 재조회이며 원격 동기화 버튼으로 해석하지 않는다.

### 2. 권한 거부

절차:
1. 앱을 처음 실행한다.
2. 캘린더 권한을 거부한다.
3. 메인 화면을 확인한다.

기대 결과:
- 빈 오류 화면으로 방치되지 않는다.
- 권한을 다시 허용하는 경로가 안내된다.
- local DB가 손상되거나 삭제되지 않는다.
- 이전에 읽었던 calendar, event, inspector 선택 내용이 화면과 메모리 state에서 제거된다.

### 3. Event Brief 저장

절차:
1. 기존 일정을 선택한다.
2. Before task를 추가한다.
3. After task를 추가한다.
4. notes를 작성하고 700ms 이내에 다른 일정으로 전환한다.
5. 다시 선택해 task 제목을 편집한 채 완료·section 이동을 실행한다.
6. 앱을 inactive로 보낸 뒤 종료·재실행한다.

기대 결과:
- 체크리스트와 notes가 유지된다.
- pending notes와 편집 중 task 제목이 화면 전환·완료·이동 전에 저장된다.
- notes 저장 실패 시 draft와 Retry가 남고 빈 상태로 위장하지 않는다.
- 같은 원본 일정에 같은 Event Brief가 연결된다.
- Calendar.app의 원본 notes에는 KaosCal 체크리스트가 쓰이지 않는다.

### 4. 새 일정 생성

절차:
1. `⌘N` 또는 toolbar plus로 `KAOS-TEST` 시간 일정을 만든다.
2. 종일 일정도 포함 종료 날짜로 하나 만든다.
3. Calendar.app을 열어 두 일정을 확인한다.
4. 만든 일정의 원본 notes와 별도 Event Brief notes를 각각 저장한다.

기대 결과:
- 새 일정이 EventKit을 통해 실제 캘린더에 저장된다.
- 원본 notes만 Calendar.app notes에 보이고 KaosCal Event Brief는 local DB에만 저장된다.
- writable calendar에만 생성할 수 있다.
- 종일 일정은 UI 포함 종료와 EventKit 배타 종료가 같은 날짜 범위를 뜻한다.
- editor가 열린 동안 두 번째 `⌘N`이 현재 draft를 교체하지 않는다.

### 5. 같은-calendar 원본 수정

절차:
1. Event Brief가 있는 일정을 선택한다.
2. 제목·시간·장소·원본 notes를 수정하고 저장한다.
3. Calendar.app과 Event Brief를 다시 확인한다.

기대 결과:
- Calendar.app 원본 필드가 바뀌고 local notes/tasks와 context_id는 유지된다.
- 원본 notes와 local notes가 서로 덮어쓰지 않는다.
- Calendar.app에서 편집기를 연 뒤 원본을 먼저 바꾸면 KaosCal 저장은 stale 오류로 중단된다.
- 제목만 바꿨을 때 structured location 등 editor 밖 metadata를 불필요하게 지우지 않는다.
- Phase 5에는 change log가 아직 생성되지 않는다.

### 6. linked calendar 이동·삭제 차단

절차:
1. Event Brief가 있는 일정을 다른 writable calendar로 옮기려고 한다.
2. 같은 editor에서 원본 삭제 control을 확인한다.

기대 결과:
- calendar picker와 delete가 잠기고 Phase 6 safe move·Phase 7 orphan review 이유가 보인다.
- EventKit update/remove를 호출하지 않고 Event Brief 상태가 바뀌지 않는다.
- local Brief가 없는 비반복 일정의 calendar 이동·삭제만 Phase 5에서 허용된다.

### 7. 읽기 전용 일정

절차:
1. subscription 또는 read-only calendar의 일정을 선택한다.
2. 편집 UI를 확인한다.

기대 결과:
- 원본 일정 편집 버튼이 비활성화된다.
- 왜 수정할 수 없는지 설명한다.
- KaosCal local Event Brief는 편집 가능해야 한다.

### 8. 원본 일정 삭제 후 orphan (Phase 7 수동 gate)

절차:
1. Event Brief가 있는 일정을 Calendar.app에서 삭제한다.
2. KaosCal로 돌아온다.
3. 동기화 또는 새로고침 후 상태를 확인한다.

기대 결과:
- Event Brief가 즉시 삭제되지 않는다.
- context가 orphaned 상태로 표시된다.
- 사용자는 보관, 재연결, 삭제 중 선택할 수 있다.

### 9. Backup / Import

절차:
1. Event Brief가 있는 상태에서 backup export를 만든다.
2. local context를 초기화한다.
3. backup을 import한다.

기대 결과:
- Event Brief가 복구된다.
- 원본 캘린더 이벤트는 import 과정에서 삭제되지 않는다.
- schema version이 맞지 않으면 안전한 오류를 보여준다.

### 10. Day / Week / Agenda 일관성

절차:
1. 같은 날짜 범위에서 Day, Week, Agenda를 각각 연다.
2. 시간 일정, 종일 일정, 반복 occurrence를 확인한다.
3. 자정을 넘는 일정과 같은 시간대에 겹치는 3개 이상의 일정을 확인한다.
4. 종일 일정이 10개 이상인 날짜에서 all-day lane을 세로로 scroll한다.
5. 이전/다음, Today, 날짜 header를 사용해 loaded range 안팎으로 이동한다.
6. 동일한 이벤트를 선택한다.

기대 결과:
- 세 화면에서 제목, 시간 또는 날짜 범위, source, 읽기 전용 상태가 일관된다.
- 종일 일정은 Day/Week의 all-day lane과 Agenda의 날짜 범위로 명확히 표시된다.
- 자정에 끝나는 일정은 다음 날에 중복되지 않고, 자정을 넘는 시간 일정은 날짜별 segment로 이어진다.
- 짧은 일정과 23:59 근처 일정도 카드가 잘리거나 같은 column에서 겹치지 않는다.
- 고밀도 timed 일정은 가로 scroll, 고밀도 종일 일정은 all-day 내부 세로 scroll로 모두 접근할 수 있다.
- 현재 시각선은 오늘 열에만 표시되고, 초기 수직 위치는 오늘 현재 시각·첫 일정·08:00 순으로 결정된다.
- loaded range 밖 이동은 새 범위를 조회하고 빠르게 되돌아오면 오래된 조회 결과가 현재 화면을 덮지 않는다.
- 선택한 Event Brief가 같은 occurrence에 연결된다.

### 10-a. 표시 달력과 DST 회귀

절차:
1. `America/New_York`의 spring-forward와 fall-back 날짜를 연다.
2. fall-back의 서로 다른 두 `01:30` occurrence를 확인한다.
3. macOS 표시 달력을 Gregorian 이외의 달력으로 바꾼 테스트 환경을 연다.

기대 결과:
- Week는 DST 날짜에도 같은 24시간 wall-clock 축을 유지한다.
- fall-back의 두 `01:30`은 같은 y 위치에서 서로 다른 column으로 보인다.
- all-day/floating 일정이 다른 연도로 이동하거나 화면에서 사라지지 않는다.
- 이 자동 배치 결과와 실제 Exchange `KC-E3` 지원 판정은 구분해 기록한다.

### 11. 시간대와 DST

절차:
1. DST 시간대의 `KC-E3 TZ` fixture를 연다.
2. 시간대를 바꾸고 `현지 시각 유지`와 `동일 시점 유지`를 각각 미리 본다.
3. spring-forward의 존재하지 않는 시각과 fall-back의 중복 시각도 `현지 시각 유지`로 시도한다.
4. 승인 가능한 결과는 Calendar.app에서 확인한다.

기대 결과:
- 두 선택이 다른 결과임을 사용자에게 보여 준다.
- floating 일정은 고정 시간대로 잘못 저장되지 않는다.
- 편집 시작 reference time zone은 sheet가 열려 있는 동안 고정된다.
- DST gap/overlap은 자동으로 한 시간 이동하거나 첫 번째 occurrence를 고르지 않고 명시적 오류로 중단한다.
- 원본 편집 실패 시 Event Brief나 change log가 잘못 갱신되지 않는다.

### 12. 반복 일정 (Phase 6 수동 gate)

절차:
1. `KC-E4 Recurring` fixture의 여러 occurrence를 연다.
2. 서로 다른 occurrence에 Brief와 task를 추가한다.
3. 이번 일정과 이번 이후 범위를 각각 변경한다.

기대 결과:
- occurrence별 Brief와 task가 섞이지 않는다.
- detached occurrence는 원래 occurrence anchor의 기존 context에 유지되고 다른 occurrence와 섞이지 않는다.
- 지원하지 않는 복잡한 서버 rule은 Calendar.app으로 안내하고 원본 rule을 훼손하지 않는다.

### 13. Task Center

절차:
1. Before/After event task와 Personal task를 만든다.
2. 오늘, 예정, 완료 목록을 차례로 연다.
3. personal due를 미래 날짜로 바꿨다가 제거한다.
4. event task 제목을 편집한 채 연결 일정을 연다.
5. 자정 또는 system time zone 변경 알림 뒤 목록을 확인한다.

기대 결과:
- event task와 personal task가 출처를 잃지 않고 한 목록에 표시된다.
- event task에는 task due와 별도로 section·원본 일정 시간·calendar/source가 표시된다.
- personal due 변경에 따라 Today/Upcoming으로 이동하고 due 없음은 Today에 포함된다.
- target range 밖 일정은 해당 범위를 fetch한 뒤 강한 occurrence match일 때만 열린다.
- weak/ambiguous/not-found이면 다른 일정을 열지 않고 local task와 오류 안내를 유지한다.
- 완료 상태와 기한이 앱 재실행 후에도 유지된다.
- Task Center 데이터는 EventKit/Exchange에 쓰이지 않는다.

### 14. 초대 일정

절차:
1. 외부 주최자가 만든 `KC-E6 Invite`와 사용자가 주최했지만 참석자가 있는 테스트 meeting을 연다.
2. Event Brief와 task를 저장한다.
3. 원본 편집 control을 확인한다.

기대 결과:
- local Event Brief는 저장할 수 있다.
- 두 일정 모두 RSVP, 참석자, 원본 제목·시간·삭제 변경 control은 보이지 않거나 비활성화된다.
- Exchange에 초대 변경 메일을 유발하지 않는다.

## 회귀 테스트 규칙

- Event Brief 데이터는 절대 `EKEvent.notes`에 serialize되지 않는다.
- read-only source에는 destructive edit control을 보여주지 않는다.
- local context 삭제는 원본 calendar event 삭제와 분리된다.
- import는 기존 DB를 경고 없이 덮어쓰지 않는다.
- 일정 이동 취소는 EventKit과 local DB 모두 변경하지 않는다.
- orphaned context는 사용자 선택 없이 자동 삭제하지 않는다.
- EventKit 변경 알림 뒤에는 마지막 loaded interval을 다시 fetch하고 stale event object를 저장하지 않는다.
- 원본 update/delete는 같은 store에서 다시 찾은 비반복 strong match와 fresh snapshot에만 실행한다.
- no-op은 EventKit save를 호출하지 않고, 변경 필드만 patch한다.
- EventKit 성공과 SQLite rebind 실패를 전체 실패로 숨기거나 local data 삭제로 보정하지 않는다.
- recurrence occurrence를 ID 하나나 UTC timestamp 하나로 잘못 연결하지 않는다.
- Task Center의 personal task는 EventKit/Exchange에 동기화하지 않는다.

## Unit test 후보

Phase 2에서 구현·통과한 항목:
- visible period 반개구간 경계와 Day/Week/Agenda filtering
- 자정 횡단 timed segment와 종일 배타 종료 column
- EventKit의 `23:59:59`/자정 all-day raw end 정규화
- timed overlap cluster, 맞닿는 일정, 최소 visual duration, 23:59 collision
- all-day span clipping, continuation, row reuse, 12행 고밀도 보존
- DST fall-back 동일 wall time column과 floating display time
- non-Gregorian display calendar 재구성
- UI occurrence ID의 이동 안정성·occurrence/calendar 구분·anonymous fallback
- loaded range 확장 조회, selection 정리, stale pending 조회 취소

Phase 3에서 구현·통과한 항목:

- `v1_context_store` migration, foreign key, CHECK, identity unique/index 계약
- 선택·빈 notes의 zero-row 보장과 첫 notes/event task의 context+link transaction 생성
- 동시 첫 notes/task 저장의 단일 context 보장
- EventContext brief 조회, EventTask CRUD·ordering·completion·fixed/relative due
- PersonalTask CRUD와 Today/Upcoming/Completed query
- event task와 personal task의 Task Center 통합 read
- normalized versioned fingerprint 일관성과 weak candidate 자동 연결 차단
- 강한 identifier 관찰 시 moved snapshot/due 갱신과 notes/task 보존
- zoned occurrence 분리와 all-day/floating civil occurrence·detached resolution
- 표시 time zone에서 all-day/floating relative due 재구성
- UTC millisecond TEXT Date raw 형식, 일반 Date binding, file DB reopen round-trip
- 완료·기한·local component·반복 identity의 파일 재열기 유지
- AppState fetch→ContextStore batch observe 연동
- hosted XCTest가 live Application Support DB를 열지 않는 bootstrap 격리

Phase 4에서 구현·자동 회귀 통과한 항목:

- lazy Brief load와 candidate/ambiguous 편집 차단
- notes debounce, 선택·mutation 전 flush, 동일 일정 refresh draft 보존
- event task add/rename/move/complete/delete와 action 전 title commit
- 일정 선택 뒤 사라지는 이전 Event Brief row도 typed task/context ID로 제목 저장
- typed Task Center ID의 event/personal completion routing과 동일 raw ID 충돌
- personal task create/rename/due update·remove/complete/delete와 Today/Upcoming 이동
- 완료 toggle의 `completed_at` 멱등성
- event-linked target range fetch, stale range task 취소, strong-only occurrence 선택
- EventKit move 뒤 Brief snapshot·Task Center default due 갱신과 pending draft 보존
- read-only/invitation의 local-only notes/task mutation
- injected clock day-boundary refresh와 display calendar 기반 날짜 문자열
- 전체 **75 tests, 0 failures, 0 unexpected**
- unsigned Release, ad-hoc signed Debug, strict codesign, app sandbox·Calendar entitlement·usage description
- in-memory DB·fake provider 1360×840 fixture의 invitation/local badge, Before/During/After·notes와 Overdue/Today/No date·event/personal row 핵심 레이아웃

Phase 5에서 구현·자동 회귀 통과한 항목:

- draft trim/range/time-zone validation, all-day 배타 종료, timed 자정 종료→all-day 경계
- 편집 시작 reference time zone 고정, 기본 zone 변경 시 all-day/floating civil rebase·semantic stale 비교, preserve-instant/local, DST gap/overlap 차단
- provider default Exchange calendar 생성과 receipt Day focus
- linked same-calendar update 뒤 context ID·notes·tasks 보존 rebind
- linked calendar 이동·삭제의 provider 호출 전 차단과 unlinked 이동·삭제 성공
- read-only, attendee meeting/invitation, recurrence 원본 editor 차단
- 외부 변경 오류에서 editor session 유지, active editor 중복 방지, 권한 회수 시 editor 제거
- pending local notes 저장 실패 시 원본 editor 차단
- EventKit 성공·local rebind 충돌 부분 성공 안내와 두 context transaction rollback
- rebind unique 충돌·missing context에서 local notes/tasks/link 보존
- 전체 **97 tests, 0 failures, 0 unexpected**, production DB mtime/size 불변

Phase 5 수동 gate와 이후 후보:

- 실제 SwiftUI 창에서 focus loss·delete confirmation·popover·VoiceOver 상호작용
- app 종료·재실행과 실제 `KAOS-TEST` event-linked navigation 수동 흐름
- 실제 `KAOS-TEST` create/update/delete, all-day, floating/zoned, Calendar.app round-trip
- event task fixed/relative due 편집 UI와 notification/reminder 정책
- ChangeLogRepository append/query
- linked calendar Move confirmation·반복 영향 범위·change log와 context_id 보존
- missing/orphaned lifecycle 전환과 relink UI
- backup/export/import/reset과 손상 DB 복구

## Beta gate

외부 베타 전에 아래 조건을 모두 통과해야 한다.

- clean checkout에서 build 성공
- 첫 실행 권한 플로우 성공
- 실제 macOS Calendar 이벤트 표시
- 병원 일정 데모 end-to-end 성공
- 앱 재실행 후 Event Brief 유지
- 일정 이동 후 context 유지와 change log 기록
- 읽기 전용 일정 설명 표시
- backup export/import 성공
- Exchange Editor/Viewer와 KC-E1~KC-E6 fixture 검증 기록
- Day/Week/Agenda와 Task Center 핵심 흐름 검증
- local DB 삭제와 원본 일정 삭제가 분리되어 있음

## 버그 리포트 형식

```text
Title:
Environment:
Build:
Calendar account type:
Steps:
Expected:
Actual:
Notes:
Attachments:
```
