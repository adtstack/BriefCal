# QA Checklist

## QA 목표

KaosCal QA의 핵심은 예쁜 캘린더가 뜨는지보다 "사용자의 일정 맥락을 잃지 않는지"를 확인하는 것이다.
특히 Event Brief 데이터가 원본 calendar notes를 오염시키지 않는지, 일정 이동과 삭제에서 context가 살아남는지 반복 검증한다.

## 테스트 환경

최소 환경:

- 깨끗한 macOS 사용자 계정
- macOS Calendar에 등록된 테스트 전용 Exchange Online 계정
- 서버 QA source `KAOS-TEST`와 destination `일정`; 두 이름은 exact match로 선택
- 수정 가능한 Exchange calendar와 공유 read-only Exchange calendar
- 네트워크가 꺼진 상태
- 권한을 거부한 상태
- 앱 재설치 또는 DB 초기화 상태

## 실계정 증거 경로와 fixture 안전

| 경로 | 용도 | 통과로 간주하지 않는 항목 |
| --- | --- | --- |
| Outlook connector server | exact-name calendar와 서버 측 CRUD·시간대·지원 반복·cleanup 확인 | TCC, EventKit `.exchange`·writable, Calendar.app, KaosCal UI·local context |
| 최신 서명 KaosCal/EventKit | full access, EventKit source·권한, Calendar.app round-trip, identifier·series 동작, local context 안전성 확인 | connector의 server pass만으로 자동 통과하지 않음 |

서버 fixture는 고유 run marker, attendee·실제 연락처 없는 내용, 제한된 날짜 범위를 사용한다. 기존 일정은 수정·삭제하지 않으며 mutation 응답으로 받은 exact fixture만 cleanup한 뒤 source/destination을 두 번 다시 조회해 잔여 0건을 확인한다. raw calendar/event ID, account/email, owner와 source title은 저장소 문서·프로젝트 로그·commit에 복사하지 않는다.

2026-07-11 run `20260711-1512-7C4E`의 서버 baseline은 source create-fetch-update, destination independent write, Pacific→Korea UTC normalization, finite weekly 5 occurrences, `this_instance` exception, exact 네 fixture cleanup과 세 번의 residue `0/0` 확인까지 pass다. `this_and_following`은 connector의 `originalStart` 누락으로 mutation 전에 fail해 재시도하지 않았고, actual cross-calendar move와 all-day는 각각 move API와 `isAllDay` create 입력이 없어 not tested다. MSA에서 search가 지원되지 않아 bounded list fallback을 사용했다. 이 baseline으로 Exchange Online이나 local EventKit pass를 선언하지 않는다.

2026-07-11 signed FinalRelease/EventKit run `20260711-1626-B7D2`에서는 full access, sidebar의 exact-name `KAOS-TEST`·`일정` `Exchange` 표시와 lock 없는 writable 상태를 확인했다. `KAOS-TEST`에 비반복 fixture를 생성하고 서버에서 한 개의 `singleInstance`, recurrence null과 UTC 정규화를 확인한 뒤, 앱 재실행·refetch에서도 반복 badge나 scope 없이 single로 유지되는 것을 검증했다. 같은 fixture를 한 번 수정해 서버 recurrence null 유지를 확인하고 scope 없는 single delete로 정리했으며 최종 marker 잔여는 source/destination `0/0`이다. Calendar.app visual round-trip, all-day, time-zone 변경, 실제 recurrence·future split, calendar move는 이 run에서 실행하지 않았다.

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

현재 증거 주의:
- 이전 signed host의 `notDetermined` gate 기록은 Exchange compatibility 문서에 역사적 증거로 보존한다.
- recurrence-fix FinalRelease run `20260711-1626-B7D2`(CDHash `63ded03a9d704976c4ba45340f2748eda9892382`)에서는 `Full calendar access`, EventKit fetch와 재실행 후 refetch, 두 exact-name calendar의 `Exchange`·writable 표시를 직접 확인했다.
- 이 결과만으로 backend를 Exchange Online이라고 판정하거나 Calendar.app visual round-trip을 통과 처리하지 않는다.

### 1-a. Sidebar mini month

절차:
1. Sidebar를 최소 폭 210pt로 줄이고 6행 mini month와 calendar 목록을 확인한다.
2. 시스템의 주 시작 요일, locale과 time zone을 바꿔 다시 확인한다.
3. 이전/다음 월로 탐색한 뒤 본문 날짜가 그대로인지 확인한다. toolbar Today와 이미 focused인 같은 spillover 날짜로 focused month 복귀를 확인하고, 현재 월과 인접 월 날짜를 각각 선택한다.
4. Day, Week, Agenda, Tasks와 선택 없는 상태에서 날짜를 선택한다.
5. keyboard focus/Space·Return과 VoiceOver 날짜 label·selected/today/adjacent value를 확인한다.

기대 결과:
- 월은 항상 42개의 연속 civil day/6행이며 DST 시작·종료와 윤년·연도 경계에서 누락·중복이 없다.
- 월 탐색만으로 본문 focused date가 바뀌지 않는다. Today나 동일 날짜 재지정도 local browse를 끝내고 focused month로 복귀한다. 날짜 선택 시 Day/Week/Agenda는 유지되고 Tasks/선택 없음은 Day로 전환한다.
- 같은 loaded range에서 현재 event가 새 visible period에도 남는 Week/Agenda 선택은 event selection과 fetch count를 유지한다. Day에서 다른 날짜를 고르거나 먼 날짜로 이동해 event가 새 visible period 밖이면 selection을 정리한다. 새 range fetch는 선택 날짜를 포함해 정확히 한 번 실행하며 EventKit create/update/delete는 없다.
- focused는 fill, today는 ring, 인접 월은 낮은 강조도로 구분되고 색만으로 상태를 전달하지 않는다.
- 긴 월 제목과 6행이 210pt에서 잘리지 않고 calendar 목록만 별도로 scroll한다.
- event dot은 완전한 42일 fetch coverage가 없으므로 표시하지 않는다.

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
1. `⌘N` 또는 toolbar plus로 source `KAOS-TEST`에 시간 일정을 만든다.
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
- linked 일정의 성공한 원본 변경은 receipt rebind와 함께 change log에 기록되고, 실패·취소·no-op에는 기록되지 않는다.

### 6. linked calendar 이동과 삭제 차단

절차:
1. Event Brief가 있는 일정을 다른 writable calendar로 옮기려고 한다.
2. 같은 editor에서 원본 삭제 control을 확인한다.

기대 결과:
- calendar 이동은 impact review를 열고, Cancel 전에는 EventKit update·local rebind·change log가 없다.
- Confirm하면 기존 context_id·notes·tasks를 유지한 채 target calendar receipt로 rebind하고 change log를 append한다.
- linked delete만 Phase 7C orphan review 이유와 함께 계속 잠긴다. local Brief가 없는 지원 일정의 이동·삭제는 허용된다.

### 7. 읽기 전용 일정

절차:
1. subscription 또는 read-only calendar의 일정을 선택한다.
2. 편집 UI를 확인한다.

기대 결과:
- 원본 일정 편집 버튼이 비활성화된다.
- 왜 수정할 수 없는지 설명한다.
- KaosCal local Event Brief는 편집 가능해야 한다.

### 7-a. 종료 일정과 After Review (Phase 7A)

절차:
1. 종료 전인 일정에 Before, During, After task와 local notes를 만든다.
2. 정확한 종료 시각에 Task Center를 새로고침한다.
3. Today, Upcoming, After Review, Completed와 선택 Event Brief를 확인한다.
4. 종일 일정의 배타 종료일, floating 일정의 system time zone 변경, 서로 다른 반복 occurrence를 확인한다.

기대 결과:
- active context는 종료 전 scheduled, `now >= end`에서 completed이며 Event Brief 상단에 `Event ended` banner와 After Review 안내가 표시된다.
- 종일은 배타 종료 자정, floating은 현재 표시 time zone의 civil end, 반복은 occurrence별 종료를 사용한다.
- Today/Upcoming에는 완료 일정의 미완료 After만 남고 Before/During row는 DB와 Event Brief에 보존된다.
- After Review에는 completed context의 미완료 After만 있고 personal task와 완료 task는 없다.
- Completed에는 완료 처리한 Before/During/After와 personal task가 기존처럼 유지된다.
- cancelled/orphaned와 non-active link는 시간 계산으로 바뀌지 않고, 자동 completed 전이에 change log가 생기지 않는다.

### 7-b. 반복 write 후 occurrence focus (Phase 7A)

절차:
1. 같은 series identifier를 공유하는 여러 occurrence를 현재 snapshot에 둔다.
2. 뒤쪽 occurrence의 title/time 같은 지원 필드를 `이번 일정`으로 수정한다.
3. provider receipt가 exact display ID를 반환하는 경우와, receipt ID가 snapshot에 없지만 강한 identifier와 occurrence anchor가 남는 경우를 각각 확인한다.
4. zoned instant, all-day civil day, floating civil date-time과 비반복 일정을 각각 확인한다.

기대 결과:
- 전체 snapshot에서 exact display ID가 있으면 다른 sibling보다 먼저 선택된다.
- exact ID가 없을 때 반복 fallback은 강한 identifier뿐 아니라 같은 calendar와 같은 occurrence anchor까지 모두 일치해야 한다.
- zoned는 절대 instant, all-day와 floating은 civil anchor를 비교해 time-zone 표시 변경으로 다른 occurrence를 선택하지 않는다.
- 비반복 write는 기존 strong-ID fallback을 유지하고, 일치하는 event가 없으면 임의 sibling을 선택하지 않는다.

### 8. 원본 일정 삭제 후 orphan (Phase 7B 수동 gate)

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

### 12. 반복 일정과 범위 확인 (Phase 6 수동 gate)

절차:
1. `KAOS-TEST`의 `KC-E4 Recurring` fixture가 attendee 없는 writable 기본 weekly rule인지 확인한다.
2. 여러 occurrence를 열고 서로 다른 occurrence에 Brief와 task를 추가한다.
3. 한 occurrence의 시간 변경을 시작하고 아직 scope를 선택하지 않은 상태를 확인한다.
4. `이번 일정`을 선택해 impact preview의 before/after, detach 가능성, 유지될 local 항목을 확인한 뒤 한 번은 Cancel하고 한 번은 Confirm한다.
5. 별도 fixture에서 `이번 이후`를 선택하고 series 영향과 affected context 수를 확인한다.
6. detached occurrence에서 `이번 이후`를 시도한다.
7. 여러 rule 또는 KaosCal이 표현할 수 없는 복잡한 server recurrence를 연다.
8. `이번 일정`에서 recurrence rule을 바꾸려 하고, unlinked basic series의 `이번 이후`에서 같은 변경을 시도한다.

기대 결과:
- occurrence별 Brief와 task가 섞이지 않는다.
- scope를 선택하고 최종 Confirm하기 전에는 EventKit provider call과 change log가 없다. Cancel 뒤 원본·local DB가 모두 그대로다.
- `이번 일정`은 선택 occurrence 하나만 바뀌고 receipt가 같은 occurrence context에 강하게 rebind된다.
- unlinked `이번 이후`는 선택 occurrence 이후만 대상으로 한다. linked `이번 이후`는 초기 Phase 6에서 전부 write 전에 차단된다.
- detached occurrence는 원래 occurrence anchor의 기존 context에 유지되고 다른 occurrence와 섞이지 않는다.
- detached occurrence의 `이번 이후`는 비활성화되고 Calendar.app 안내가 보인다.
- 지원하지 않는 복잡한 서버 rule은 `이번 이후`와 rule 변경을 Calendar.app으로 안내한다. `이번 일정`의 ordinary-field 변경은 recurrence rule을 훼손하지 않고 저장된다.
- attendee meeting/invitation에는 recurrence scope 원본 control이 제공되지 않는다.
- `이번 일정`은 recurrence rule 변경을 허용하지 않고, unlinked basic series의 `이번 이후`만 rule 변경 후보가 된다. linked series rule 변경은 초기 Phase 6에서 차단된다.

### 12-a. linked safe move와 change log (Phase 6 수동 gate)

절차:
1. destination `일정`과 attendee·recurrence가 없는 source `KAOS-TEST` fixture를 사용한다. `일정`이 비어 있다고 가정하지 않는다.
2. fixture에 non-sensitive Event Brief notes와 Before/During/After task를 각각 하나 이상 저장한다.
3. target calendar를 `일정`으로 바꾸고 impact confirmation을 연다.
4. 기존/새 calendar·시간, 유지할 local notes/task 요약과 최근 change history를 확인한 뒤 Cancel한다.
5. 다시 열어 Confirm하고 Calendar.app·KaosCal·Task Center를 확인한다.
6. 같은 fixture에 외부 변경을 만든 뒤 남아 있는 Undo 또는 후속 write를 시도한다.

기대 결과:
- Cancel에는 EventKit update, local rebind, change log append가 없다.
- Confirm 뒤 원본만 target calendar로 이동하고 동일한 `context_id`, notes, tasks가 유지된다.
- `moved` log의 before/after calendar·time과 `single` scope가 남는다. 원본 EventKit notes와 Event Brief notes는 서로 덮어쓰지 않는다.
- EventKit 성공 뒤 local transaction 실패를 주입하면 원본 성공·local 갱신 실패·local data 보존·false log 없음이 함께 표시된다.
- 후속 성공 write, 권한 철회, 앱 재실행 뒤에는 이전 session Undo를 제공하지 않는다. 외부 변경 알림 뒤 button이 남더라도 실행 시 provider가 stale/missing/read-only를 감지해 local mutation 전에 차단한다.
- linked original delete는 여전히 비활성화되고 Phase 7C orphan review 이유가 보인다.

### 12-b. 좁은 session Undo (Phase 6 수동 gate)

절차:
1. 지원 가능한 비반복 `single` linked move 또는 시간 변경을 Confirm한다.
2. 같은 event가 선택된 inspector의 `Undo Last Event Change`를 한 번 실행한다.
3. 성공 뒤 button과 change history를 확인한다.
4. 새 mutation 뒤 이전 Undo, 앱 재실행 뒤 Undo, 외부 Calendar.app 변경 뒤 Undo, recurrence·detached·delete의 Undo를 확인한다.

기대 결과:
- button은 같은 strong event와 in-memory candidate가 있을 때만 보이며 중복 실행할 수 없다.
- Undo action은 현재 원본이 직전 after snapshot과 같을 때만 역방향 EventKit write를 실행한다.
- 성공하면 기존 change row는 삭제되지 않고 `undone`이 되며 별도 `restored` row가 원본 change를 참조한다.
- 같은 context의 새 mutation은 이전 `available`을 `superseded`로 바꾼다.
- session token이 없거나 stale하면 persistent log만 보고 Undo를 다시 만들지 않는다.
- 일반 store refresh가 token을 즉시 지우지 않아도 external after-snapshot mismatch는 provider에서 역방향 write 전에 중단된다.
- 반복 `thisEvent`/`futureEvents`, series split, detached occurrence, delete에는 Undo가 없다.

### 13. Task Center

절차:
1. Before/After event task와 Personal task를 만든다.
2. 오늘, 예정, After Review, 완료 목록을 차례로 연다.
3. personal due를 미래 날짜로 바꿨다가 제거한다.
4. event task 제목을 편집한 채 연결 일정을 연다.
5. 자정 또는 system time zone 변경 알림 뒤 목록을 확인한다.

기대 결과:
- event task와 personal task가 출처를 잃지 않고 한 목록에 표시된다.
- event task에는 task due와 별도로 section·원본 일정 시간·calendar/source가 표시된다.
- personal due 변경에 따라 Today/Upcoming으로 이동하고 due 없음은 Today에 포함된다.
- 종료 일정의 열린 Before/During은 Today/Upcoming에서 숨기되 삭제·자동 완료하지 않고, After만 After Review에서 처리할 수 있다.
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
- 원본 update/delete는 같은 store에서 다시 찾은 strong match와 fresh snapshot에만 실행한다. 반복 write는 지원 가능한 rule과 명시적 scope·Confirm을 추가로 요구한다.
- 반복 소속은 `hasRecurrenceRules || isDetached`로만 판정한다. `occurrenceDate`는 반복 identity anchor이며 비반복 display event에서는 `nil`이어야 한다. 새 single `EKEvent`의 synthetic `occurrenceDate == startDate`가 반복 badge·scope·write route를 만들지 않는지 회귀 테스트한다.
- no-op은 EventKit save를 호출하지 않고, 변경 필드만 patch한다.
- EventKit 성공과 SQLite rebind 실패를 전체 실패로 숨기거나 local data 삭제로 보정하지 않는다.
- recurrence scope와 impact Confirm 전에는 provider와 change log를 호출하지 않는다.
- linked future-series는 초기 Phase 6에서 provider 호출 전에 차단한다. 후속 reconciliation이 추가되어도 weak·ambiguous·missing이면 계속 차단한다.
- persistent `undo_state = available`은 앱 재실행 뒤 Undo 권한이 아니다.
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

Phase 5 이후에도 남은 수동·후속 후보:

- 실제 SwiftUI 창에서 focus loss·delete confirmation·popover·VoiceOver 상호작용
- app 종료·재실행과 실제 `KAOS-TEST` event-linked navigation 수동 흐름
- 실제 `KAOS-TEST` create/update/delete, all-day, floating/zoned, Calendar.app round-trip
- event task fixed/relative due 편집 UI와 notification/reminder 정책
- missing/orphaned lifecycle 전환과 relink UI
- backup/export/import/reset과 손상 DB 복구

Phase 6에서 구현·통과한 자동 gate:

- `v2_event_change_log` additive migration, FK/CHECK/index와 immutable v1 유지
- versioned before/after payload의 zoned/all-day/floating/recurrence round-trip
- mutation impact의 task count·recent history와 side-effect-free read
- rebind+log atomic transaction, unique/foreign-key 실패 rollback, EventKit 부분 성공 안내
- `single`/`this_event`/`future_events` scope routing과 Confirm 전 provider call 0회
- detached future, attendee, complex recurrence future/rule 변경, 모든 linked future preflight 차단과 complex this-event rule 보존
- context ID·notes·tasks를 보존하는 linked move/this-event reconciliation
- available→superseded, available→undone+restored와 one-shot session token 무효화
- 반복·detached·delete Undo 금지와 stale after-snapshot 역방향 write 차단
- EventKit save 뒤 post-save occurrence receipt를 확정하지 못한 부분 성공에서 editor/review 종료, refresh, 동일 write 재시도 차단과 local data·log 불변
- detached ordinary edit의 과거 recurrence end 허용과 all-day/floating reference-zone drift에서 변경하지 않은 recurrence end 보존
- 전체 **121 tests, 0 failures, 0 unexpected**, unsigned Release·ad-hoc signed Debug·strict codesign 통과
- 자동 test 전후 production DB 불변. signed app bootstrap에서는 sandbox DB에 `v2_event_change_log`가 additive 적용되고 integrity/FK 정상·change log 0행임을 별도로 확인

Phase 6 signed FinalRelease corrective live gate:

- 새 비반복 `EKEvent`가 recurrence rule 없이도 `occurrenceDate == startDate`를 노출하는 실동작을 재현하고, occurrence date를 반복 membership으로 사용해 잘못된 badge·scope가 생기는 원인을 수정
- 반복 membership을 `hasRecurrenceRules || isDetached`로 통일하고, `occurrenceDate`는 반복 identity anchor로만 유지하며 single display event에서는 `nil`로 정규화
- synthetic occurrence date single, 순수 membership matrix, protocol default scope routing, legacy Brief 정상화를 포함해 전체 **132 tests, 1 intentional skip, 0 failures**
- 최종 build-only compatibility Release CDHash `511a11258d95a49c826b49dc463a79039707807e`, `codesign --verify --deep --strict`·hardened runtime **pass**. 아래 live run은 직전 recurrence-fix artifact CDHash `63ded03a9d704976c4ba45340f2748eda9892382`에서 수행
- live run `20260711-1626-B7D2`: full access, `KAOS-TEST`·`일정` Exchange/writable 표시, `KAOS-TEST` nonrecurring create, server `singleInstance`·recurrence null·UTC normalization, app restart/refetch single 표시, single update와 server recurrence null 유지, single delete **pass**
- exact marker cleanup 뒤 source/destination 잔여 `0/0`
- full test와 live QA 전후 direct/sandbox production DB 및 각 `-wal`·`-shm` 상태 **불변**
- 과거 synthetic anchor 오분류로 recurring identity가 저장된 Brief는 strong identifier와 calendar/title/location/time/fingerprint/anchor가 모두 같은 single에만 자동 연결하고 `single:v1`로 갱신. notes/tasks 보존, navigation read-only. legacy 구조와 strong identifier는 맞지만 snapshot이 달라졌으면 자동 연결 없이 확인 필요 후보, identifier가 없으면 기존 exact/fingerprint 후보 정책 유지
- Calendar.app visual round-trip, live all-day, time-zone 변경, recurrence occurrence·future split, calendar move는 이 gate에서 **not tested**이며 beta 지원 근거로 올리지 않음

Phase 7A lifecycle·focus 자동/Release gate:

- active occurrence의 zoned/all-day/floating 유효 종료, 반복 occurrence별 독립 lifecycle, cancelled/orphaned와 non-active link 보존, Today/Upcoming/After Review/Completed projection 검증
- exact display ID 우선과 same-calendar + instant/civil occurrence anchor 반복 fallback, 비반복 strong-ID fallback 검증
- 전체 **145 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**; result bundle `/private/tmp/KaosCalPhase7AFull.xcresult`
- build-only Release `/private/tmp/KaosCalPhase7ARelease/Build/Products/Release/KaosCal.app`, CDHash `abfb685b03f1ff919f83a955e5b819e3c6b57df6`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**
- exact Release의 1360×840 onscreen 창 bootstrap과 종료 후 process 0 확인. 전체 test와 bootstrap 전후 direct/sandbox production DB mtime·size·SHA-256 및 WAL/SHM 부재 불변
- 이 gate에서는 EventKit/Exchange write를 실행하지 않았으며, Screen Recording 권한 부재로 픽셀 캡처는 시각 레이아웃 pass 근거로 사용하지 않음

Mini month 자동/Release gate:

- Sunday/Monday-first, 윤년·연도 경계, New York DST 시작/종료, LA/Tokyo absolute-date 차이와 42개 고유 civil identifier 검증
- 같은 범위·먼 범위 날짜 선택의 selection/fetch 경계와 provider create/update/delete 0회 검증
- `MiniMonthView`를 Sidebar 최소 폭 210×240, German locale, Monday-first로 직접 offscreen render해 6행·인접 월·focused/today 상태와 잘림 없음 확인. 전체 `NavigationSplitView` offscreen 결과는 sidebar가 렌더되지 않아 근거에서 제외
- 전체 **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**; post-review result bundle `/private/tmp/KaosCalMiniMonthPostReview.xcresult`
- build-only Release `/private/tmp/KaosCalMiniMonthRelease/Build/Products/Release/KaosCal.app`, CDHash `92e16853c099db014b3f3f2d370d0b57ba44bc90`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**
- exact Release의 1482×931 onscreen 창 bootstrap과 종료 후 process 0 확인. 전체 test와 bootstrap 전후 direct/sandbox production DB mtime·size·SHA-256 및 WAL/SHM 부재 불변
- 이 gate에서는 EventKit/Exchange write를 실행하지 않았으며, live Exchange 증거는 run `20260711-1626-B7D2`와 분리

App icon asset/Release gate:

- `AppIcon.appiconset/Contents.json`의 10개 macOS slot이 16, 32, 64, 128, 256, 512, 1024px PNG와 정확히 일치하고 모두 square alpha PNG인지 확인
- 네 corner alpha 0, center alpha 255, full-bleed squircle edge와 내부 green spill 부재를 확인해 macOS 14/15 legacy `.icns`에서 opaque square가 되지 않게 한다.
- 16·32·64·128px를 실제 크기와 확대 보기로 확인해 off-white calendar와 apricot check silhouette이 남고 글자·숫자·watermark가 없는지 확인
- Release build에 `AppIcon.icns`, `Assets.car`, `CFBundleIconFile = AppIcon`, `CFBundleIconName = AppIcon`이 포함되는지 확인
- Finder/Dock light·dark wallpaper와 clean-machine beta에서 system mask, contrast, 캐시 갱신을 수동 확인. layered/dark/tinted Icon Composer variant는 현재 gate 밖
- AppIcon 추가가 EventKit/Context DB를 쓰지 않고 기존 전체 154-test gate를 바꾸지 않는지 확인
- 최초 opaque build는 자동·서명 gate 통과와 별개로 macOS 14/15 risk 때문에 candidate에서 제외
- transparent correction 최종 자동 결과: **154 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**; result bundle `/private/tmp/KaosCalAppIconCompatFinal.xcresult`
- 최종 build-only Release `/private/tmp/KaosCalIconCompatRelease/Build/Products/Release/KaosCal.app`, CDHash `bc2ddd83c9d7f5e1bfd62241b0e02e63b23308b6`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**
- `AppIcon.icns` 역추출 16/32/128/256px alpha, corner 0/center 255, Info.plist icon keys, Assets.car와 XCTest 비포함 확인
- exact Release의 1512×949 onscreen 창, NSWorkspace valid icon, 종료 후 process 0 확인. 테스트·bootstrap 전후 direct/sandbox production DB와 WAL/SHM 상태 불변

상세 명령·artifact·DB 수치와 실계정 미검증 상태는 구현 로그와 Exchange compatibility 문서에 기록한다.

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
