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

2026-07-12 Phase 7C run `20260712-025027-KST`에서는 exact signed Release에서 linked 비반복 fixture의 impact review·Back no-write·final delete 1회, Calendar.app/Outlook 원본 제거, `Original deleted · Local Brief kept`, Notes와 Before/During/After task 보존, no Undo와 current-link-generation deletion provenance를 확인했다. 서버 최종 residue는 single 0, recurring 0이다. 별도 recurring series는 서버 생성·cleanup만 통과했고 UI 진입 전 macOS session 자동 잠금으로 `thisEvent` mutation은 not tested다. retained single local Brief의 UI-only cleanup도 다음 수동 세션에 남아 있다.

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
6. 현재 42일 바깥의 월을 빠르게 연속 탐색해 loading→완료와 stale 응답 무시를 확인한다. 0개·단일·복수, 자정에 끝나는 일정, 자정을 넘는 timed multi-day와 all-day 일정을 월 경계와 spillover 첫·끝 셀에 배치한다. Calendar Set과 calendar visibility도 각각 바꾼다.

기대 결과:
- 월은 항상 42개의 연속 civil day/6행이며 DST 시작·종료와 윤년·연도 경계에서 누락·중복이 없다.
- 월 탐색만으로 본문 focused date가 바뀌지 않는다. Today나 동일 날짜 재지정도 local browse를 끝내고 focused month로 복귀한다. 날짜 선택 시 Day/Week/Agenda는 유지되고 Tasks/선택 없음은 Day로 전환한다.
- 같은 loaded range에서 현재 event가 새 visible period에도 남는 Week/Agenda 선택은 event selection과 fetch count를 유지한다. Day에서 다른 날짜를 고르거나 먼 날짜로 이동해 event가 새 visible period 밖이면 selection을 정리한다. 새 range fetch는 선택 날짜를 포함해 정확히 한 번 실행하며 EventKit create/update/delete는 없다.
- focused는 fill, today는 ring, 인접 월은 낮은 강조도로 구분되고 색만으로 상태를 전달하지 않는다.
- 긴 월 제목과 6행이 210pt에서 잘리지 않고 calendar 목록만 별도로 scroll한다.
- 42일 전체 조회 성공 전에는 grid 전체 dot이 숨겨지고 loading/unavailable 상태가 `일정 없음`과 구분된다.
- coverage 완료 뒤 일정이 있는 날짜에는 숫자 아래 단일 dot이 표시된다. focused date는 흰색, 일반 날짜는 accent, 인접 월은 낮은 opacity이며 숫자·fill·ring과 겹치지 않는다.
- timed multi-day와 all-day 일정은 배타 종료를 지켜 겹치는 각 civil day에 dot을 만든다. 자정에 끝나는 일정은 다음 날에 표시하지 않으며 hide+block은 세지 않고 show+ignore는 센다. 선택 Set 밖의 일정도 제외한다. 여러 일정도 dot은 하나지만 VoiceOver value는 정확히 `일정 N개`를 전달한다.
- 월 탐색과 요약 조회는 본문 focused date·현재 event snapshot을 바꾸거나 EventKit create/update/delete를 호출하지 않는다.

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

### 6. linked calendar 이동과 원본 삭제 review

절차:
1. Event Brief가 있는 일정을 다른 writable calendar로 옮기려고 한다.
2. 같은 editor에서 원본 삭제를 선택하고 첫 alert의 `Review Deletion Impact`를 연다.
3. 원본 title/date/calendar/scope와 보존될 notes, Before/During/After task 수·제목, 최근 history를 확인한다.
4. Back/Cancel과 별도 fixture의 `Delete Original & Keep Brief`를 각각 실행한다.

기대 결과:
- calendar 이동은 impact review를 열고, Cancel 전에는 EventKit update·local rebind·change log가 없다.
- Confirm하면 기존 context_id·notes·tasks를 유지한 채 target calendar receipt로 rebind하고 change log를 append한다.
- linked delete의 첫 alert, review와 Back은 provider/local write 0회다. final destructive Confirm만 EventKit delete를 호출한다.
- nonrecurring은 `single`, recurring은 명시적 `thisEvent`만 가능하며 linked `futureEvents`, attendee/invitation과 read-only 원본은 provider 전에 차단된다.
- successful receipt 뒤 context는 cancelled, link는 orphaned이고 같은 context_id·notes/tasks·saved link snapshot이 남는다. unavailable `cancelled` log의 before/after는 같은 saved-link payload, originalNotes는 nil/unavailable, Undo는 없다.
- Task Center와 recovery sheet는 상태쌍에 더해 current-link-generation KaosCal deletion log가 있을 때만 `Original deleted · Local Brief kept`를 표시한다. 이후 `(created_at, rowid)`상 더 늦은 relink는 과거 deletion provenance를 무효화하고 Relink/local Brief delete 진입점은 유지한다.
- provider 성공 뒤 local CAS/log 실패를 주입하면 local transaction 전체와 false log가 rollback되고 editor/review가 닫힌다. 원본은 이미 삭제됐을 수 있으므로 동일 Delete를 재시도하거나 자동 복원하지 않고 local data 보존을 알린다.
- local Brief가 없는 지원 일정의 기존 이동·삭제 경로는 그대로 유지된다.

현재 live 증거:

- run `20260712-025027-KST`, Asia/Seoul; exact signed Release `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6b1da198f969cb033946fdb72b2b2e46392310f2`
- `KAOSCAL-P7C-LIVE-20260712-025027-KST-SINGLE`, 2026-07-12 15:00–16:00 KST, attendee·recurrence 없음. Notes 1건과 Before/During/After task 각 1건은 앱 재실행 뒤에도 유지
- first alert와 final review가 `Scope: Single event`와 local Notes/task 수를 표시. Back 뒤 provider/local write 없음, Outlook exact-marker count 1 유지
- final delete 정확히 1회 뒤 Task Center의 `Original deleted · Local Brief kept`, Notes, task 3개, no Undo, Relink/Delete Local Brief 진입점 확인
- Outlook exact-marker 즉시·지연 count 0, Calendar.app exact title 검색 `결과 없음`
- sandbox DB `query_only` 확인에서 integrity/FK/migration 통과, context/link 1/1과 `cancelled`/`orphaned`, Notes와 section별 task 1개, 정확히 1개의 `cancelled`/`single`/`unavailable` log, available Undo 0, matching payload·current deletion provenance, 전후 동일한 보존 combined hash 확인. 실제 hash와 본문은 기록하지 않음
- recurring marker `KAOSCAL-P7C-LIVE-20260712-025027-KST-RECUR`는 서버에서 `seriesMaster`와 2026-07-12~14 daily occurrence 3개를 확인하고 전체 cleanup했다. UI 진입 전 session lock으로 `thisEvent` mutation은 **not tested**이며 제품 failure가 아님
- 최종 서버 residue single 0, recurring 0. retained single local Brief는 session lock 때문에 UI-only cleanup 대기이며 다음 수동 세션에서 삭제 후 원본 비재생성을 확인해야 함

### 7. 읽기 전용 일정

절차:
1. subscription 또는 read-only calendar의 일정을 선택한다.
2. 편집 UI를 확인한다.

기대 결과:
- 원본 일정 편집 버튼이 비활성화된다.
- 왜 수정할 수 없는지 설명한다.
- KaosCal local Event Brief는 편집 가능해야 한다.

### 7-c. Multi-calendar clarity와 saved Calendar Set

절차:
1. `KAOS-TEST`와 `일정`에 서로 다른 role을 지정하고 All/Work/Personal Smart Role Filter를 전환한다.
2. 사용자 이름의 saved Set을 둘 이상 만들고 순서·이름을 바꾼다. 겹치는 membership과 Work/Personal 혼합 membership, 빈 Set을 각각 만든다.
3. Settings에서 account별 Include All/Remove All과 개별 membership을 바꾸고, 전역 Enabled를 끈 뒤 membership이 보존되는지 확인한다. Block도 독립적으로 바꾼다.
4. 선택한 saved Set을 재실행 뒤 복원하고, active Set 삭제 시 All fallback을 확인한다. calendar identifier가 사라진 membership은 authoritative loaded/empty 상태에서만 unavailable로 남는지, loading·permission denied·failure에서는 missing으로 단정하지 않는지, 같은 이름 calendar에 자동 연결하지 않는지, 명시적 Replace/Remove만 적용되는지 확인한다.
5. 같은 제목이며 시작·종료가 각각 15분 이내인 다른-calendar 일정, 같은 all-day civil range인 일정과 경계 밖 일정을 준비한다. filter 밖 calendar에 원본 create/update한 뒤 focus도 확인한다.
6. Sidebar, Day, Week, Agenda, Inspector, 원본 editor와 Task Center의 role/source/account/permission 표시를 비교한다.
7. invitation, attendee, subscription, birthdays와 provider read-only fixture에서 원본 편집을 시도한다.

기대 결과:
- role 변경은 local `calendar_preferences`만 갱신하고 EventKit create/update/delete를 호출하지 않는다. Set 전환도 원본 fetch·Event Brief·Task Center row를 삭제하지 않는다.
- 현재 Set 밖의 선택은 pending notes를 저장한 뒤 안전하게 정리된다. relink/duplicate 또는 성공한 write focus 대상이 normal filter 밖일 때만 persisted Set 선택을 All로 덮어쓰지 않고 exact 일정을 임시 reveal한다.
- `visibleEvents = global Enabled ∩ selected Set`이다. saved Set membership을 변경하거나 calendar를 globally disable해도 서로의 저장값을 삭제하지 않고, availability blocking도 Set과 독립이다.
- saved Set은 exact calendar identifier만 사용한다. missing membership은 보존하고 title/source 유사성으로 자동 rebind하지 않는다.
- source가 있는 subscribed/birthdays만 기본 `Subscription`, 나머지는 `Other`다. source와 explicit override가 모두 없으면 account type을 추측하지 않고 `Other`로 표시한다.
- timed/all-day duplicate는 다른 calendar의 검토 후보로만 표시되고 strong same occurrence, 제목/시간 범위 밖 항목은 제외된다. 자동 merge·hide·delete와 EventKit write는 없다.
- typed reason 우선순위는 invitation→attendee→subscription→birthdays→provider read-only이며 UI 설명과 원본 write preflight가 같다. local Event Brief는 계속 편집 가능하다.
- 작은 card는 icon, 자세한 role/source/reason은 help·VoiceOver와 Inspector에 남는다. 44pt 고밀도와 210pt Sidebar, 긴 한국어/source명은 실제 화면에서 잘림과 VoiceOver 순서를 별도 확인한다.

### 7-d. Calendar visibility와 availability blocking

절차:
1. 같은 account source 아래 둘 이상의 calendar를 준비하고 Settings의 Calendars tab을 연다.
2. 각 calendar를 show+block, show+ignore, hide+block, hide+ignore 네 조합으로 설정한다.
3. busy, free, tentative, canceled, current-user-declined와 availability 미지원 event를 준비한다.
4. Sidebar eye, Settings account bulk action, Day/Week/Agenda와 blocked interval projection을 비교한다.
5. 앱을 재실행하고 backup export/import/reset 뒤 설정을 다시 확인한다.

기대 결과:
- account group은 EventKit source identifier를 사용하며 source title이 같아도 다른 identifier를 합치지 않는다.
- hide는 Day/Week/Agenda와 현재 선택만 정리하고 raw fetch, Event Brief observation/relink, duplicate와 editor destination을 줄이지 않는다.
- hide+block event는 화면에 없지만 blocking projection에는 남고 show+ignore event는 화면에 보이지만 blocking에는 없다.
- free, canceled와 current-user-declined event는 block하지 않는다. busy, tentative, unavailable과 availability 미지원 event는 blocking calendar에서 block한다.
- 겹치거나 맞닿은 block interval은 union되어 중복 calendar/event가 시간을 이중 가중하지 않는다.
- 기본값은 모든 calendar show, subscribed/birthdays ignore, 나머지 account type block이다. read-only만으로 ignore하지 않는다.
- explicit usage만 `calendar_usage_preferences`에 sparse 저장하고 마지막 override reset에서 row를 삭제한다. 어떤 설정도 EventKit create/update/delete를 호출하지 않는다.

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

### 8. 원본 일정 삭제 후 missing/orphan 복구 (Phase 7B 수동 gate)

절차:
1. Event Brief가 있는 일정을 Calendar.app에서 삭제한다.
2. KaosCal로 돌아와 해당 Brief를 연다.
3. 전용 lookup의 첫 `notFound` 뒤 상태를 확인한다.
4. `Check Again`을 누르기 전 일반 Reload와 범위 이동만 수행한다.
5. 명시적으로 `Check Again`을 눌러 두 번째 `notFound`를 만든다.
6. `Keep as orphan`, exact event 재연결, local Brief 삭제를 각각 독립 fixture로 확인한다.

기대 결과:
- Event Brief가 즉시 삭제되지 않는다.
- 첫 `notFound`에서는 link만 missing이며 context와 notes/tasks가 보존된다.
- 일반 범위 fetch 부재, Reload, provider 오류, weak/ambiguous 후보, 권한 문제는 두 번째 miss로 세지 않는다.
- 명시적 재확인의 두 번째 `notFound` 뒤에만 사용자가 orphan 보관, 재연결, local 삭제 중 선택할 수 있다.
- orphan 보관 뒤 context와 link가 orphaned로 남고 Task Center의 `Local Event Briefs`에서 다시 열 수 있다.
- 재연결은 최종 provider exact 검증 뒤 기존 notes/tasks와 context ID를 유지하며 새 link snapshot에 붙는다.
- local 삭제 확인에는 notes/tasks 영향이 표시되고, 실행 전후 EventKit 원본과 provider write count가 변하지 않는다.

### 9. Backup / Import

절차:
1. Event Brief notes/tasks, personal task, change history, explicit calendar role·usage와 saved Set/membership/selection이 있는 healthy current-schema file DB에서 수동 export를 만든다.
2. ZIP root가 store-only `kaoscal.sqlite`, `manifest.json` 정확히 두 entry인지 확인하고 manifest 64 KiB, DB 128 MiB, archive 129 MiB 상한을 각각 시험한다.
3. manifest의 archive format version이 schema version과 분리돼 있고 app/export metadata, v1~v9 migration 목록, DB byte count와 SHA-256이 snapshot과 일치하는지 확인한다. 기기 이름이 없는지도 확인한다. SHA-256은 제작자 인증이 아님을 문구로 확인한다.
4. active DB 내용을 구분할 수 있게 바꾼 뒤 export ZIP import를 선택하고 replacement confirmation을 취소해 no-op을 확인한다.
5. 다시 승인해 import 전 `Backups` automatic ZIP 생성, validated hot restore와 projection reload를 확인한다.
6. extra/nested/duplicate entry, deflate/encryption/data descriptor/ZIP64/multi-disk, extra/comment/attribute, trailing/gapped/overlapping payload, manifest 누락·변조, byte/hash 불일치, unknown archive format, incompatible schema/migration, corrupt SQLite, integrity/FK failure fixture를 각각 import한다. 다시 압축한 ZIP과 신뢰할 수 없는 출처도 성공 경로로 취급하지 않는다.
7. pending notes 저장 실패, 진행 중 event mutation, automatic-backup 경로 실패 상태에서 import/reset을 시도한다.
8. reset sheet에서 틀린 문자열과 `RESET`을 각각 입력한다. 성공 전후 모든 current user-data table과 migration history를 확인한다.

기대 결과:
- 정상 export ZIP에는 정확히 두 store-only entry만 있고 manifest byte/hash가 DB와 일치한다.
- app identifier, current schema object와 migration 목록이 정확히 같은 신뢰 가능한 backup만 import한다. 과거 schema 자동 migration이나 미래 schema downgrade, SHA-256만으로 제작자 신뢰 판정은 하지 않는다.
- import cancellation과 모든 preflight 실패는 active DB, WAL/SHM과 EventKit provider write count를 바꾸지 않는다.
- valid import는 Event Brief/tasks/personal tasks/change log/role·usage/saved Set·membership·selection을 복구하고 import 직전 DB의 automatic ZIP 경로를 결과에 표시한다.
- restore 또는 사후 schema/integrity/FK failure는 사전 snapshot으로 rollback하고 partial active DB를 성공으로 표시하지 않는다.
- reset은 automatic backup이 먼저 성공한 경우에만 실행되며 provider/reference row, `event_change_log`, event task/link/context, personal task, calendar role·usage, saved Set·membership·selection을 포함한 KaosCal user row를 비운다. schema와 GRDB migration history는 유지한다.
- export/import/reset 어느 경로도 Calendar/Exchange 원본 일정이나 EventKit provider write count를 바꾸지 않는다.
- 현재 UI는 linked title/time/location/identifier와 original-notes change snapshot이 plaintext ZIP에 포함될 수 있고 complete calendar record/account credential/Exchange password는 전용 export 대상이 아니라고 설명한다. KaosCal이 credential/token과 attendee 전체 목록을 전용 필드로 저장하지 않는다는 점, 사용자 notes/tasks는 검사·redact하지 않아 본문 민감정보가 포함될 수 있다는 점도 Settings copy와 backup 정책에 구현됐다. run `20260712-1616-KST`에서 Settings 전체 scroll과 실제 Export/Import panel 문구를 확인했다.
- `Backups`의 recovery ZIP은 자동 삭제·prune되지 않는다.
- 정상 store를 열지 못하는 failed-bootstrap corrupt DB 상태에는 Settings import를 성공 경로로 표시하지 않는다. 이 recovery UI는 Phase 10이다.

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
- 이 Phase 6 gate에서는 linked original delete가 비활성화되고 Phase 7C 이유가 보이는 역사적 경계를 확인했다. 현재 삭제 review/finalize는 위 6번과 아래 Phase 7C gate에서 별도로 검증한다.

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

### 13. Task Center와 오른쪽 Tasks

절차:
1. Before/After event task와 Personal task를 만든다.
2. Today, Upcoming, Overdue, No Date, After Review와 Completed를 차례로 연다.
3. personal due를 미래 날짜로 바꿨다가 제거한다.
4. event task 제목을 편집한 채 연결 일정을 연다.
5. 자정 또는 system time zone 변경 알림 뒤 목록을 확인한다.
6. provider destination이 있는 event task에서 linked/pending, remote 삭제 missing,
   version conflict와 권한 철회 disconnected를 차례로 만든다. 각 Resolve 메뉴를 실행한다.
7. 오른쪽 `Tasks`를 처음 열어 Reminders 권한 요청을 허용한다. 별도 test user에서는 먼저
   거부한 뒤 같은 화면의 `Open System Settings`로 복구한다.
8. `All Lists`를 열어 Apple Reminders, Google Tasks, Todoist와 Microsoft To Do의 source/account/list 구분과
   불러온 전체 task 수를 확인한다. 서로 raw list ID가 같은 두 provider list와 같은
   provider에서 account만 다른 같은 raw list ID도 번갈아 선택한다.
9. 선택한 list에서 Open/Completed/All, 제목·설명 검색과 Due date/Priority/Title 정렬을 조합한다.
   선택한 list를 provider에서 삭제한 뒤 authoritative reload도 실행한다.
10. inspector를 300pt와 360pt 폭으로 줄여 긴 제목·설명·list/account 이름을 확인한다.
11. list, Completed와 Title 정렬을 선택한 채 Details로 갔다 돌아오고 앱을 재실행한다.
12. `All Lists`에서 `+`를 누르고 iCloud와 `On My Mac` writable list를 각각 선택해
    생성→제목·notes·기한 수정→완료→미완료→삭제한다. 종료 뒤 두 list에 residue가 없는지
    Reminders.app에서 확인한다.
13. writable Apple Reminder 행의 완료 원을 빠르게 두 번 누르고, 행을 열어 상세 source와
    전체 notes·기한·완료를 확인한다. 같은 이름의 list가 있으면 account/source를 구분한다.
14. 상세 draft를 연 채 Reminders.app에서 같은 task를 수정하고 Save한다. conflict에서 draft가
    남고 `Reload Latest`/`Cancel`만 보이는지 확인한다. 이어 list를 read-only로 바꾸거나
    삭제하고, Reminders 권한도 철회했다가 복구한다.
15. inspector를 300pt와 360pt, 상세 sheet를 keyboard와 VoiceOver로 순회한다. 완료 버튼,
    list picker, title/notes/due/completed, Save/Delete/Cancel, 오류·복구 문구를 확인한다.
16. linked task의 local 제목과 remote 제목을 각각 다르게 수정한 뒤 refresh한다. 이어 remote
    task를 삭제하고 다시 refresh한다.
17. 연결된 Event Brief task의 provider write가 실패하도록 네트워크를 끊어 durable pending
    create/update/delete를 만든 뒤 앱을
    재실행한다. Retry를 반복해 세 번째 실패와 이후 비활성 상태를 확인한다.
18. Resolve 또는 provider action menu에서 `Link to Existing Remote Task…`를 열고 서로 다른
    provider/account/list의 같은 이름 task를 번갈아 선택한다. 검색과 source 문구도 확인한다.
19. linked task에서 `Keep Local Only`를 선택하고 앱을 재실행한 뒤 local task를 수정한다.
    원격 task는 그대로인지 확인하고 `Use Calendar Default Provider`로 다시 연결한다.
20. calendar의 기본 destination을 다른 provider/list로 바꾼다. 기존 linked task와 변경 당시
    unbound task를 수정하고, 변경 뒤 새로 만든 task도 수정한다.
21. Google Tasks, Todoist와 Microsoft To Do의 writable test list에서 각각 생성→제목·notes·
    기한→완료→미완료→삭제를 실행한다. Google due의 시간 미지원, Todoist/Microsoft의 원본
    열기, Todoist project↔section 이동·Undo, Apple/Microsoft/Todoist priority와 Microsoft
    reminder 설정/제거를 함께 확인한다.
22. local Event/Personal task에 priority·중요 표시·반복 간격·예상 시간을 설정하고 timer를
    시작/정지한다. checklist를 만들고 반복 task를 완료한다.
23. role, 날짜 filter, 날짜/list grouping과 검색을 조합해 이름 있는 Task view를 저장하고
    다시 선택한다. 같은 검색어로 Calendar와 아직 연결하지 않은 provider task가 함께
    검색되는지 확인한다.
24. provider task를 Day/Week의 시간 칸으로 끌어 놓는다. 생성된 1시간 event block과 During
    task, provider binding을 확인한다. 현재 Calendar Set에 writable calendar가 없을 때도 확인한다.
25. Event Brief에서 `Link Existing Provider Task…`를 사용하고 Before/During/After 기한을
    fixed, event start 전/후, event end 전/후로 바꾼다. 원본 일정을 이동하고 연결 영향
    미리보기를 확인한다.
26. 오른쪽 Tasks의 `Current Calendar Set Only`를 켜고 Set을 바꾼다. 연결 일정 열기와 task
    reschedule을 실행하고 완료되지 않은 task의 대상 날짜를 바꾼다.

기대 결과:
- event task와 personal task가 출처를 잃지 않고 한 목록에 표시된다.
- event task에는 task due와 별도로 section·원본 일정 시간·calendar/source가 표시된다.
- personal due 변경에 따라 Today/Upcoming/Overdue/No Date가 정확히 분리되며 due 없음은
  Today가 아니라 No Date에만 포함된다.
- 종료 일정의 열린 Before/During은 Today/Upcoming에서 숨기되 삭제·자동 완료하지 않고, After만 After Review에서 처리할 수 있다.
- target range 밖 일정은 해당 범위를 fetch한 뒤 강한 occurrence match일 때만 열린다.
- weak/ambiguous/not-found이면 다른 일정을 열지 않고 local task와 오류 안내를 유지한다.
- 완료 상태와 기한이 앱 재실행 후에도 유지된다.
- provider 연결 task는 provider·계정·list와 상태를 텍스트로 표시한다. missing은 재확인
  또는 local 기준 remote 재생성, conflict는 remote/local 명시 선택, disconnected는
  Settings 복구를 제공하며 실패를 linked로 표시하지 않는다.
- local과 remote가 각각 바뀌면 어느 쪽도 자동 덮어쓰지 않고 conflict가 된다. remote 삭제는
  local task를 보존한 missing이며 새 remote task를 자동 생성하지 않는다. remote-only 제목,
  완료와 지원 가능한 due 변경은 한 local transaction으로 반영된다.
- pending은 앱 재실행 뒤 operation·attempt count·마지막 오류를 유지한다. 명시적 Retry는 최대
  3회이고, exact relink 또는 local-only로 빠져나갈 수 있다.
- relink sheet는 provider/account/list/source를 함께 보여 주며 최종 exact lookup과 다른 local
  task 소유 검사를 통과한 선택만 binding과 local projection을 원자적으로 교체한다.
- `Keep Local Only`는 binding/pending만 제거하고 원격 task를 삭제하지 않으며 재실행 뒤에도
  자동 sync하지 않는다. 기본 destination을 다시 쓰는 동작은 실제 enabled/authorized
  destination이 있을 때만 local-only를 해제한다.
- destination 변경은 기존 binding의 provider/list를 옮기지 않는다. 변경 당시 unbound task는
  local-only로 남고 변경 뒤 새 task만 새 destination을 사용한다.
- 오른쪽 `Tasks`는 패널 전체 높이를 채운다. 미결정 권한은 첫 진입에서 요청하고, 거부는
  System Settings 복구를 제공한다. 허용 뒤 task가 없어도 상단 연결 표시가 보인다.
- `All Lists`는 빈 list까지 metadata 기준으로 보여 주고 provider가 다른 같은 raw list ID를
  섞지 않는다. 선택한 list에서는 그 list 작업만 보이며 이름 변경에는 선택이 유지되고
  삭제 뒤에는 `All Lists`로 안전하게 돌아간다.
- 상태·검색·정렬을 함께 적용해도 결과와 count가 일치한다. 좁은 폭에서 control이 잘리지
  않고 제목은 최대 2줄, 설명은 1줄, due·overdue는 텍스트와 아이콘으로 구분된다.
- 선택 list·상태·정렬은 Details 왕복과 재실행 뒤 복원되고, 검색어는 초기화된다. OAuth
  list 조회 중에는 선택이 사라지지 않으며 일시 오류에는 마지막 metadata/loaded task
  fallback을 유지한다.
- writable provider task는 지원 capability 범위에서 완료 원, `+`와 상세 sheet의 생성·제목·
  notes·기한 설정/제거·완료·삭제를 원본에 반영하며 Open filter에서는 성공한 완료 행만
  사라진다. Google Tasks의 due는 날짜만 저장되고 Apple/Microsoft/Todoist priority는 의미를
  보존한다. Microsoft reminder는 due와 독립적으로 설정·제거된다. 목록 이동은 Apple
  Reminders의 writable list/account와 같은 Todoist account의 project/section에서만 노출한다.
- version conflict는 원격을 자동 덮어쓰거나 재시도하지 않고 draft, `Reload Latest`, Cancel을
  유지한다. read-only, metadata 실패, 외부 삭제와 권한 철회는 write 없이 Refresh 또는
  Reminders 개인정보 설정 복구를 제공한다. 연결 remote 삭제는 local Event Task를
  Needs attention으로 보존한다.
- Microsoft To Do와 Todoist는 provider가 반환한 신뢰 가능한 URL이 있을 때만 원본 열기를
  제공한다. Apple EventKit에는 task별 신뢰 가능한 Reminders URL이 없으므로 약속하지 않는다.
  각 실제 provider fixture cleanup 뒤 생성한 remote residue가 남지 않는다.
- local planning metadata와 checklist는 v11 SQLite/backup/reset에 포함되고 provider가 지원하지
  않는 field로 전송되지 않는다. 반복 완료는 다음 local occurrence를 만들고 checklist를
  미완료로 복사하며 실제 수행 시간을 초기화한다.
- task drag는 현재 Set의 writable calendar에 15분 단위, 기본 1시간 block을 만들고 During
  task와 exact provider identity를 연결한다. 연결 일정 이동은 상대 기한을 다시 계산하며
  삭제는 provider task나 local Event Task를 조용히 삭제하지 않는다.
- saved Task view와 list/status/sort 선택은 재실행 뒤 복원되며, Task Center는 linked local
  projection과 연결되지 않은 provider task를 중복 없이 함께 검색한다.
- Personal task와 Event Brief 원문은 EventKit/Exchange calendar에 쓰이지 않는다.
  configured event task의 provider mutation만 선택한 task provider로 전달된다.

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
- import는 기존 DB를 경고 없이 덮어쓰지 않고 automatic recovery ZIP이 실패하면 restore를 시작하지 않는다.
- archive는 store-only two-entry 구조, format/schema/migration 분리, byte/SHA-256, integrity/FK를 모두 통과해야 한다.
- local snapshot/restore는 같은 live SQLite writer를 사용하고 DB/WAL file replacement로 우회하지 않는다.
- reset은 모든 current user-data table row를 지우고 migration history를 유지하며, reset 전 automatic backup이 필수다.
- backup/import/reset은 EventKit write를 호출하지 않는다.
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
- 실제 `KAOS-TEST` 비반복 create→update→delete는 통과했다. 남은 live 후보는 all-day, floating/zoned 의미 보존과 Calendar.app 시각 round-trip
- event task fixed/relative due 편집 UI와 notification/reminder 정책
- 실제 Exchange 동기화 지연·외부 삭제에서의 missing/orphan/relink UI 수동 흐름
- 실제 `KAOS-TEST` linked original `single`/`thisEvent` 삭제, Calendar.app·Outlook 반영, no-retry 부분 성공과 crash-window recovery
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

Phase 7B missing/orphan/relink 자동 gate:

- 저장 link의 zoned instant, all-day·floating civil anchor를 만드는 전용 occurrence-aware lookup과 same-calendar exact strong match를 검증
- 첫 명시적 `notFound`는 missing만, 별도 재확인의 두 번째 `notFound`만 orphan review를 열며 error·candidate·ambiguous·inconclusive는 miss로 세지 않음을 검증
- 어느 calendar에서든 recurrence/occurrence shape가 맞지 않는 strong seed, 멀리 이동한 detached/recurring occurrence와 불완전한 series seed는 false orphan 대신 보수적 inconclusive/candidate로 남기고 legacy synthetic recurring→single은 확인 후보로만 반환
- provider cancelled evidence는 context cancelled로 보존하고, 이후 exact found라는 새 positive evidence가 있을 때 scheduled/completed로 복구함을 검증
- orphan 자동 재활성화 금지, explicit keep/relink/local delete transaction, stale expected-link CAS, 최종 provider exact 검증, 식별자 없는 후보 차단, unique/log-insert 실패 rollback을 검증
- 재연결 뒤 기존 notes/tasks와 context ID가 보존되고 Event Brief를 즉시 다시 불러오며, local 삭제의 provider create/update/delete 호출이 모두 0임을 검증
- Task Center의 모든 local Brief 목록에서 notes-only active와 missing/orphan 상태에 접근하고, background strong recovery 뒤 stale recovery sheet가 닫힘을 자동 검증. recovery sheet의 긴 local notes는 line limit을 제거하고 text selection을 유지했음을 코드 검토
- 전체 **175 tests, 1 intentional opt-in skip, 0 failures, 0 unexpected**; Debug result bundle `/private/tmp/KaosCalPhase7BFinal-20260712-0155.xcresult`
- build-only Release `/private/tmp/KaosCalPhase7BFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `f3b30718434641dbbd2dbec90f82581342d47506`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**; get-task-allow와 XCTest 비포함
- exact Release의 1482×931 onscreen 창 bootstrap과 정상 종료 뒤 process 0 확인. 전체 test와 bootstrap 전후 direct/sandbox production DB mtime·size·SHA-256 및 WAL/SHM 부재 불변
- 실제 Exchange 외부 삭제·동기화 지연, 후보 재연결과 recovery sheet의 전체 시각 상호작용은 수동 gate로 남는다. 이 Phase 7B checkpoint 당시 KaosCal 내 linked original delete는 Phase 7C까지 비활성화했다.
- 살아 있는 recurring series의 one-off 삭제와 범위 밖 detached move는 bounded EventKit lookup으로 구분할 수 없어 automatic orphan 수동 gate의 통과 범위에서 제외하고 manual exact relink만 확인

Phase 7C linked original delete fake-provider/local DB 자동 gate:

- active Brief의 notes/tasks/history, exact expected link와 saved-link change snapshot을 한 read에서 준비하고 Confirm 직전 full link/snapshot CAS를 반복함을 검증
- first alert, review, Back/Cancel, stale preflight, invalid scope와 provider failure에는 provider/local write와 log가 모두 0임을 검증
- nonrecurring `single`과 recurring `this_event` success, linked `futureEvents` provider 사전 차단, context `cancelled` + link `orphaned`, notes/tasks/context ID/last-known snapshot 보존을 검증
- `cancelled` log의 동일 before/after saved-link payload, originalNotes nil/unavailable, previous available Undo supersede, 새 log unavailable과 process Undo 무효화를 검증
- deleted-original projection은 `cancelled + orphaned`만으로 만들지 않고 current-link-generation unavailable `cancelled` log를 요구함을 검증. 뒤따르는 relink는 `(created_at, rowid)` 순서로 과거 provenance를 무효화하며 동일 timestamp rowid tie-break와 relink 뒤 외부 cancelled/orphaned 비표시를 포함
- final expected-link CAS 또는 log insert 실패의 local 전체 rollback, successful provider 뒤 editor/review 종료·refresh·no-retry partial-success message와 false log 부재를 검증
- deleted-original Task Center/recovery projection을 일반 orphan과 구분하고 Relink/local Brief delete 진입점을 유지함을 검증
- Phase 7C 신규 회귀 총 14개를 포함한 전체 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**; result bundle `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult`
- build-only Release `/private/tmp/KaosCalPhase7CFinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6b1da198f969cb033946fdb72b2b2e46392310f2`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**; get-task-allow와 XCTest 비포함
- production DB open을 차단한 exact binary 스모크는 5초 이상 생존하고 종료 뒤 process 0. 전후 direct/sandbox DB mtime·size·SHA-256과 WAL/SHM 부재 불변. computer-use runtime 부재로 onscreen 시각 검증은 미실행
- 이 자동 checkpoint 당시에는 EventKit/Exchange fixture delete, Calendar.app/Outlook 반영, process crash 재현이 **not tested**였다. 후속 비반복 live 결과는 바로 아래 별도 gate에 기록하며 process crash는 계속 미검증이다.
- v1 `cancelled`/`orphaned`, v2 `cancelled` change type·기존 scope/undo를 재사용해 schema migration을 추가하지 않았다.

Phase 7C linked original delete live Exchange gate:

- run `20260712-025027-KST`, Asia/Seoul; exact Phase 7C signed Release와 CDHash를 자동/Release checkpoint와 동일하게 고정
- full access, `KAOS-TEST`·`일정` exact `Exchange` writable preflight **pass**
- nonrecurring linked fixture의 restart persistence, review·Back no-write, final delete 1회, Task Center deleted-original projection과 Notes/task 보존 **pass**
- Outlook immediate/delayed exact-marker 0과 Calendar.app exact title `결과 없음` **pass**
- sandbox DB read-only integrity/FK/migration, retained context/link, lifecycle/status, Notes·section task counts, exact unavailable cancellation log, no available Undo, matching payload·current provenance와 보존 hash equality **pass**; 실제 hash·본문 미기록
- automatic evidence는 **189 tests executed, 188 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**와 `/private/tmp/KaosCalPhase7CFinal-20260712-022700.xcresult` 그대로 유지
- recurring server fixture는 `seriesMaster`와 daily occurrence 3개 생성·전체 cleanup, residue 0 **pass**. session auto-lock 이전에 UI에 진입하지 못해 recurring `thisEvent` mutation은 **not tested**, 제품 failure 아님
- 서버 최종 residue single 0, recurring 0. retained single local Brief의 `Delete Local Brief`와 원본 비재생성 확인은 **manual pending**

Phase 8 Multi-Calendar Clarity 자동·Release gate(당시 All/role runtime filter 범위):

- conservative role inference, explicit sparse role 저장·재열기·delete/reset과 v1/v2→`v3_calendar_clarity` additive migration, role CHECK를 검증
- 당시 virtual Set filtering, selection 밖 전환 전 notes flush, Task Center/duplicate 후보의 All 전환과 calendar identifier 기반 role projection을 검증
- invitation·attendee·subscription·birthdays·provider read-only typed precedence와 같은 reason을 쓰는 AppState 원본 write preflight, provider write 0회를 검증
- normalized title, timed 15분 경계, all-day civil range, cross-calendar/strong-occurrence 제외, deterministic candidate index를 검증. index는 fetch 때 한 번 만들고 card lookup은 O(1)
- 최종 전체 **199 tests executed, 198 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**; result bundle `/private/tmp/KaosCalPhase8FinalTests-20260712-1415.xcresult`
- signed Release `/private/tmp/KaosCalPhase8FinalRelease/Build/Products/Release/KaosCal.app`, CDHash `6c595445dadfb60588410329222557d00865c222`, strict codesign·hardened runtime·sandbox·Calendar entitlement **pass**; get-task-allow와 XCTest 비포함
- 전체 test 전후 direct/sandbox 운영 DB의 mtime·size·SHA-256과 WAL/SHM 부재 불변. exact Release 정상 bootstrap에서는 사전 backup 뒤 sandbox DB만 v2→v3로 migration하고 integrity `ok`, FK violation 0, 새 table 0행과 기존 다섯 table count·SHA3 불변, 종료 뒤 process 0을 확인
- macOS session lock 때문에 Sidebar/Inspector/고밀도 card/VoiceOver 실화면은 **not tested**. shared read-only Viewer가 없어 provider read-only reason live gate도 **manual pending**이며 자동 결과로 대체하지 않음

Saved Calendar Set v9 gate:

- `v9_saved_calendar_sets` additive migration, CRUD·rename·delete·reorder, exact membership 중복/CASCADE, singleton selection과 active-delete All fallback을 검증한다.
- global Enabled master mask, saved Set overlap·mixed role·empty/unavailable empty state, membership 보존, explicit missing Replace/Remove와 no title-based auto-rebind를 검증한다.
- duplicate/relink temporary reveal이 persisted selection을 바꾸지 않는지, backup/import/reset이 Set 데이터를 보존·정리하는지, fake provider write 0회인지 검증한다.
- Settings/Sidebar keyboard, shortcut `⌃1`/정렬된 첫 8개 saved Set의 `⌃2`~`⌃9`, 긴 이름·account group·unavailable row와 VoiceOver는 실제 창 gate를 별도로 기록한다.
- 집중 ContextStore/LocalDataBackupService는 **84 executed / 84 succeeded / 0 skipped /
  0 failed**, 전체 suite는 **248 executed / 247 succeeded / 1 intentional manual-only skip /
  0 failed**이며 두 action status 모두 `succeeded`다. result bundle은 각각
  `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-34-47-+0900.xcresult`,
  `/tmp/KaosCalCalendarSetsDataTests/Logs/Test/Test-KaosCal-2026.07.15_18-36-07-+0900.xcresult`다.
- 이 자동·offscreen checkpoint 뒤 AppState review 수정 3건이 적용됐다. 수정 후 build와
  UI/post-write를 포함한 focused **73 tests / 0 failures**는 통과했으며 result bundle은
  `/tmp/KaosCalCalendarSets/Logs/Test/Test-KaosCal-2026.07.15_18-53-22-+0900.xcresult`다.
  최신 최종 전체는 **257 executed / 256 passed / 1 intentional manual-only skip / 0 failures**이며
  result bundle은 `/tmp/KaosCalTasksFilters-Final-R2-20260716.xcresult`다.
- 실제 Exchange saved Set CRUD/rebind와 Settings/Sidebar 실창·keyboard·VoiceOver는 계속
  manual pending이다. 이전 237-test checkpoint는 v9 통과 근거로 사용하지 않는다.

Phase 9 Local Data 자동·Release gate:

- 당시 집중 자동 검증은 live-writer export snapshot, standard `unzip -t` 호환 two-entry ZIP, manifest v1 핵심 값, same-writer import, pre-import automatic ZIP의 실제 재복구, 당시 six-table reset·migration history 유지와 pre-reset ZIP의 실제 재복구를 포함한다.
- hostile fixture는 input symlink, CRC/path traversal/attribute, trailing byte, multi-disk, encryption/data descriptor/deflate/ZIP64/overlap/oversize, 예상 밖 schema object, 숨은 `sqlite_*` trigger와 미등록 migration ledger 행을 거부한다. export destination은 live DB와 WAL/SHM/journal, hard link, symlink parent 경유까지 차단한다.
- AppState 집중 자동 검증은 pending selected notes를 flush한 export, import/reset 성공 뒤 local projection reload, automatic ZIP의 별도 DB 복구와 export/import/reset의 fake provider write 0회를 확인한다. 주입한 import/reset `rollbackSucceeded = false`는 local/provider mutation과 refresh를 session quarantine으로 차단한다.
- file-backed healthy DB로 620×620 Settings bitmap 생성과 fitting size를 확인했다. 이 자동 결과 자체는 실제 panel·scroll·typed reset을 대신하지 않으며, 별도 live run `20260712-1616-KST`에서 해당 상호작용을 확인했다.
- manifest exact-key/type/version/hash 변조, 손상 SQLite가 integrity/FK 검사까지 도달하는 fixture, automatic-backup 생성 실패, core restore/post-validation 실패 뒤 실제 rollback, failed draft·열린 interaction·concurrent operation 차단과 repeated deterministic encode는 구현 계약과 별도 QA 항목이다. 전용 fixture가 추가되기 전에는 자동 통과로 기록하지 않는다.
- plaintext·무서명·수동 retention, source machine name 부재, 계정 credential 전용 저장 부재와 사용자 notes/tasks 무검열 포함 계약은 문서/code review와 run `20260712-1616-KST`의 실제 Settings/file-panel copy 확인 범위다.
- 최종 전체 **213 tests executed, 212 passed, 1 intentional ManualEventKitQATests skip, 0 failures, 0 unexpected**; result bundle `/private/tmp/KaosCalPhase9FinalTests-20260712-1535.xcresult`.
- signed Release `/private/tmp/KaosCalPhase9FinalRelease-20260712-1535/Build/Products/Release/KaosCal.app`, CDHash `4f6eb184110ca317a440c5d640cf0670e4c42753`, strict codesign·hardened runtime·sandbox·Calendar·user-selected read/write entitlement **pass**; get-task-allow와 XCTest 비포함.
- exact Release는 1512×949 visible window를 만들었고 직접 종료했다. direct DB `1783704658|126976`, SHA-256 `69b4a9c7d61782c005cd461df6716ac4fd6215a014e4807f21fd5d6988fdfa1d`와 sandbox DB `1783832834|139264`, SHA-256 `7cd91d35ceaa7f04a43c00e88cf1c99d7d8f778ebeffa8c55af0f9f269251d23`가 test·bootstrap 전후 불변이며 integrity `ok`, FK violation 0, WAL/SHM/journal 부재와 최종 process 0을 확인했다.
- 후속 live run `20260712-1616-KST`에서 exact Release의 620×652 Settings 전체 scroll, 880×448 Export/Import panel, 470×256 reset sheet와 `RESET` 입력 뒤 Delete 활성화를 **pass**했다. 모든 panel과 sheet는 취소했으며 실제 export/import/reset과 EventKit/Exchange write는 실행하지 않았다.
- production DB open/migration 실패 상태의 bootstrap recovery는 이 gate에 포함하지 않고 Phase 10으로 유지한다.

Phase 10 Paid Beta Polish 자동·수동 gate:

- 첫 실행 onboarding이 Calendar password/MFA 비수집, local Event Brief, plaintext backup과
  핵심 shortcut을 읽을 수 있게 표시하고 680×560 안에서 잘리지 않는지 확인
- Day/Week에 event가 없을 때 grid를 유지하면서 명시적 empty-period 안내가 보이고,
  `⌘R`이 현재 Tasks 또는 Calendar reload로 라우팅되는지 확인
- invalid/corrupt/incompatible archive는 live DB byte와 `Recovery` 폴더를 만들기 전에
  거부되는지 확인
- valid current-schema archive는 기존 DB와 존재하는 WAL/SHM/journal을 같은 고유
  quarantine folder로 이동하고 restored DB의 schema/integrity/FK와 fixture rows를 확인
- replacement 설치/재오픈 검증 실패를 주입하면 새 파일군을 제거하고 원본 DB와 모든
  sidecar byte를 되돌리는지 확인. rollback 자체 실패는 success로 표시하지 않음
- bootstrap recovery가 EventKit provider write를 만들지 않고 성공 뒤 새 `AppState`가
  일반 shell을 여는지 확인
- signed Release의 실제 file panel, 손상 test-user DB, successful recovery와 quarantine,
  invalid backup no-touch, power-loss/crash window는 별도 live/fault gate로 기록
- onboarding/recovery의 keyboard focus order, Return/Escape, 긴 오류·경로, light/dark,
  Reduce Motion/Increase Contrast와 VoiceOver label/action을 실제 창에서 확인
- Developer ID/notary/staple/package/clean-user 설치, approved EULA와 support/privacy/security
  contact가 없으면 자동·offscreen 통과와 무관하게 외부 beta를 차단
- 현재 자동 checkpoint: **220 executed / 219 passed / 1 intentional manual-only skip /
  0 failures / 0 unexpected**, `/private/tmp/KaosCalPhase10Tests.xcresult`
- 현재 ad-hoc Release: `/private/tmp/KaosCalPhase10Release/Build/Products/Release/KaosCal.app`,
  CDHash `4d7c1b5ad6dde65666f101cae00bdcb9d5b878ed`; Developer ID/notarized artifact가 아님

Mini month 자동/Release gate:

- 아래 증거는 event-dot 확장 이전 gate이며 `CAL-007`/`UI-005` 구현 통과 근거가 아니다.
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
