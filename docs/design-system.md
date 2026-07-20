# Design System

## 디자인 방향

KaosCal의 톤은 Calm Pro Calendar다.
바쁜 사용자가 하루의 일정을 빠르게 읽고, 어떤 일정에 어떤 맥락이 붙어 있는지 바로 판단할 수 있어야 한다.

BusyCal의 정보 밀도, 빠른 탐색, 3-pane 작업 흐름은 참고한다. 그러나 KaosCal은 BusyCal의 색, 아이콘, 화면 구성, 브랜드 요소를 복제하지 않는다.

## 제품 느낌

- 차분하다.
- 고밀도 정보를 견딘다.
- Mac 네이티브 앱처럼 반응한다.
- 장식보다 판독성을 우선한다.
- 일정의 출처와 권한을 숨기지 않는다.

## 앱 아이콘

- calendar grid는 일정 탐색, 겹친 schedule block은 고밀도 계획, apricot
  checkmark는 Event Brief와 Todo 완료를 나타낸다.
- midnight navy 배경, steel blue 일정, off-white calendar, warm apricot
  action의 네 역할만 사용한다. 앱 accent `#2B7099`와 같은 계열이다.
- 글자·숫자·특정 날짜·외부 서비스 표식은 사용하지 않는다.
- square master의 핵심은 중앙 70% 안에 둔다. macOS 14/15 legacy `.icns`를
  위해 canvas edge까지 닿는 full-bleed squircle과 transparent corner를
  포함하고, 최신 system mask와 겹쳐도 줄어들지 않도록 별도 margin은 두지
  않는다. 16px에서도 흰 calendar와 apricot check silhouette이 남아야 한다.
- 현재 asset catalog는 16~1024px flattened alpha PNG다. layered/dark/tinted
  Icon Composer variant는 외부 배포 polish에서 검토한다.

## 기본 레이아웃

```text
┌────────────────────────────────────────────────────────────────────┐
│ KaosCal      ◀ Today ▶      Wed, Jul 1      Day Week Month Agenda │
├──────────────┬──────────────────────────────────────┬──────────────┤
│ Mini Month   │                                      │ Event Brief  │
│              │          Week Calendar               │              │
│ Calendars    │                                      │ 치과 진료     │
│ ● Work       │    10:00  ▌ Team Sync                │ Fri 15:00    │
│ ● Personal   │    11:00  ▌ Dentist                  │ Personal     │
│ ● Family     │    12:00                             │              │
│              │    13:00  ▌ Lunch                    │ Before       │
│ Calendar Sets│    14:00  ▌ Design Review            │ ☐ 신분증      │
│ All Calendars│    15:00                             │ ☐ 보험 서류   │
│ My Focus     │                                      │              │
└──────────────┴──────────────────────────────────────┴──────────────┘
```

## 3-pane 규칙

Sidebar:
- 고정 6×7 mini month 날짜 탐색기
- role·source·permission을 함께 보여 주는 calendar list와 role 변경 menu
- synthetic `All Calendars`, 사용자 저장 Calendar Set, role별 Smart Role Filter
- Set은 global Enabled와 교집합으로 현재 Day/Week/Agenda visibility를 좁힌다. 승인된 `UI-005`에서는 mini month 일정 존재 표시에도 같은 filter를 적용하며 EventKit fetch·Event Brief·editor destination은 제거하지 않는다.

Calendar Area:
- Day/Week/Agenda는 모두 v1 필수
- Day/Week에는 종일 일정용 all-day lane
- Month는 v1에서 가볍게 시작하거나 후순위
- today indicator 명확히 표시

Event Brief Panel:
- 선택 일정의 title/time/source
- Before/During/After
- KaosCal notes
- change history 요약은 Phase 6 impact review에서 우선 표시하고, 상시 전체 history panel은 후속 polish로 둠
- read-only 설명

Task Center:
- sidebar 항목으로 열고 오늘·예정·After Review·완료를 빠르게 전환
- event task에는 연결 일정의 시간, role, calendar/source를 작게 표시
- personal task에는 로컬 저장 badge를 표시
- 프로젝트·팀 collaboration UI는 제공하지 않음

## Event card 규칙

```text
┌────────────────────────────┐
│▌ Design Review             │
│▌ 14:00-15:00 · Work        │
└────────────────────────────┘
```

- 왼쪽 rail에 calendar color 사용
- 전체 배경색은 subtle system fill 사용
- 제목은 한두 줄까지 허용
- 시간과 calendar role을 작은 metadata로 표시
- read-only 또는 possible duplicate는 화면 밀도에 맞는 icon/text·help·VoiceOver로 표시하고 색상만으로 전달하지 않는다.

### Phase 2 실제 적용값

- 시간축: 24시간, 시간당 56pt, 30분 보조선
- 시간 gutter: 64pt
- Week 날짜 최소 너비: 112pt
- overlap column 최소 너비: 44pt; 더 좁아지면 날짜 열을 늘려 가로 scroll
- timed card: 최소 22pt, 3pt calendar rail, 5pt radius, 선택 시 2pt outline
- 높이 34pt 미만은 제목 중심, 34pt 이상은 시간, 58pt 이상은 role·calendar title까지 표시한다. 생략 정보는 tooltip과 VoiceOver label에 모두 남긴다.
- all-day row: 26pt, card 22pt. lane은 내용에 맞춰 늘지만 화면 높이의 35%·최대 240pt에서 내부 세로 scroll로 전환한다.
- 오늘 열은 약한 accent fill, 현재 시각은 red line과 dot으로 표시한다.
- calendar rail은 EventKit calendar의 실제 sRGB color snapshot을 사용한다. 색을 가져올 수 없을 때만 Exchange 공통 blue 또는 secondary gray를 fallback으로 쓴다.
- Phase 8의 calendar role과 Smart Role Filter, v9의 사용자 이름 saved Set을 적용했다. 사용자 color override는 아직 구현 범위가 아니다.

### Mini month 적용값과 승인된 확장

- Sidebar `List` 위에 고정하고 calendar 목록만 독립적으로 scroll한다.
- Sidebar 최소 폭 210pt에서 바깥 padding 12pt, 7열 간격 2pt, 날짜 최소 높이 24pt, 요일 header 최소 높이 16pt를 사용한다.
- 월은 항상 42개 civil day/6행이다. 현재 calendar의 첫 요일 순서, locale과 time zone을 사용하며 DST에서도 calendar day 연산으로 날짜를 만든다.
- 월 화살표는 본문 날짜를 바꾸지 않고 mini month만 탐색한다. 날짜 선택은 Day/Week/Agenda를 유지하고 Task Center에서는 Day로 이동한다.
- 다른 월을 둘러보는 중 toolbar Today 또는 이미 focused인 같은 날짜를 다시 선택해도 focused month로 복귀한다.
- focused date는 accent 원형 fill과 흰 숫자, today는 accent ring, focused+today는 흰 inset ring, 인접 월은 secondary와 낮은 opacity로 표시한다.
- 모든 날짜와 월 화살표는 `Button`이고 grid는 keyboard focus section이다. 날짜 접근성 label은 요일+전체 날짜, value는 focused/today/adjacent 상태, identifier는 calendar civil key를 쓴다.
- 일정이 하나 이상 있는 날짜는 숫자 아래에 지름 3pt 단일 event dot을 둔다. 숫자, focused fill과 today ring에는 겹치지 않는다.
- focused date의 dot은 흰색, 일반 날짜는 accent, 인접 월 날짜는 같은 accent에 낮은 opacity를 사용한다. 일정이 없으면 dot을 그리지 않으며 일정 수가 여러 개여도 시각 표시는 하나로 유지한다.
- dot 요약은 `global Enabled ∩ 선택 Calendar Set`을 적용하고 availability blocking과는 독립이다. 따라서 disable+block 일정에는 dot이 없고 enable+ignore 일정에는 dot이 있다. timed multi-day와 all-day 일정은 배타 종료를 지켜 겹치는 모든 civil day에 표시한다.
- 표시 중인 42일 전체 fetch coverage가 성공한 뒤 grid 단위로 dot을 공개한다. 부분 결과를 섞지 않으며 loading/failure를 `일정 없음`으로 표현하지 않는다.
- dot은 별도 hit target이나 접근성 element가 아니다. 날짜 Button의 접근성 value에는 `일정 N개`를 포함하고, grid는 loading/unavailable 상태를 별도로 전달한다.

## Event Brief 규칙

Before:
- 준비물
- 출발/준비 알림
- 사전 자료

During:
- 회의 중 확인할 항목
- 현장에서 처리할 항목

After:
- 후속 작업
- 영수증/기록 보관
- 다음 일정 예약

빈 상태:
- 과한 설명보다 바로 추가할 수 있는 입력 상태를 제공한다.
- 병원/회의/출장 템플릿은 Phase 4 이후 검토한다.

### Phase 4 실제 상호작용

- 원본 일정 badge와 `Event Brief · Local editable` badge를 분리한다. read-only·invitation이어도 local Brief 입력은 잠그지 않는다.
- notes는 700ms debounce로 저장하고 `Waiting to save…`, `Saving…`, `Saved on this Mac`, `Not saved · Retry`를 notes 바로 아래에 표시한다.
- Before/During/After는 각 섹션에 항상 inline add row를 둔다. task 제목은 Return·focus loss에 저장하고 완료·이동·원본 열기 전에 먼저 commit한다.
- task checkbox는 원형 outline/filled check를 사용하고 완료 시 제목에 취소선을 표시한다.
- 개별 task 삭제는 확인 alert를 거치며 `The calendar event will not be changed`를 명시한다. 전체 Brief 삭제 UI는 제공하지 않는다.
- `due_kind = none` event task는 `Follows event`로 표시한다. Before/During은 시작, After는 종료 시각을 따른다. fixed/relative due editor는 후속 범위다.
- identity candidate/ambiguous 상태는 빈 Brief로 위장하지 않고 편집을 중단한 safety card와 설명을 표시한다.

### Task Center 실제 상호작용 (Phase 4 + Phase 7A)

- toolbar의 날짜 이동 control을 숨기고 `Task Center`와 local reload만 표시한다. 목록 기준일은 사용자가 이동한 calendar focused date가 아니라 현재 시각이다.
- 상단 segmented control로 Today/Upcoming/After Review/Completed를 전환한다.
- Today는 Overdue/Today/No date, Upcoming은 날짜별, After Review는 종료 일정의 미완료 후속 작업, Completed는 최근 완료 group으로 표시한다.
- completed Event Brief는 inspector 상단에 `Event ended` banner와 After Review 안내를 표시한다. 전체 Before/During 기록은 Brief에 남기되 Today/Upcoming에는 열린 After만 보인다.
- After Review에는 personal composer를 표시하지 않는다. 이 목록은 새 개인 task 입력 화면이 아니라 종료 일정 후속 작업 처리 화면이다.
- row는 checkbox, inline title, task due, event section·원본 일정 범위·calendar/source 또는 `Personal · Local`, due edit, delete 순서다.
- personal quick-add는 제목·선택 due를 받는다. Upcoming에서는 내일 이후 due가 필수이고, due 변경 시 Today/Upcoming의 해당 목록으로 이동한다.
- due는 정렬·분류 metadata이며 reminder notification을 생성하지 않는다.
- event source를 누르면 target range를 불러온 뒤 강한 occurrence match만 Day 화면에서 연다. 못 찾으면 task는 유지하고 오류를 표시한다.
- loading, empty, query failed를 서로 다른 상태로 표시하며 실패에는 Retry를 제공한다.

### 오른쪽 Tasks inspector

- 이름은 `Tasks`로 유지하고 inspector 전체 높이를 사용한다. 상단에는 연결 상태, Apple
  Reminder 생성 `+`, refresh를 두고 성공 상태를 반복하는 별도 행은 만들지 않는다.
- 전체 폭 `All Lists` menu는 Apple Reminders와 Microsoft To Do를 source section으로
  나누고 list·account·불러온 전체 task 수를 표시한다. 같은 표시 이름은 안정된 list ID
  순서의 `List 1`, `List 2` 보조 표기로 구분한다.
- list 선택은 `(provider, accountKey, listID)` identity를 사용한다. 선택한 list에서는
  section을 반복하지 않고 해당 task만 평면 목록으로 표시한다.
- list 아래에는 inline search, Open/Completed/All segmented control, 결과 수와 Due date/
  Title 정렬을 이 순서로 둔다. 검색은 제목과 설명에 적용한다.
- 행은 system content background와 separator를 사용하고 제목은 body medium 최대 2줄,
  설명과 due는 subheadline으로 둔다. 설명은 1줄과 전체 help를 함께 제공하며 날짜 없는
  task에 반복적인 `No date`를 쓰지 않는다.
- overdue는 빨간색만 쓰지 않고 아이콘, `Overdue` 텍스트와 날짜를 함께 제공한다. task
  접근성 label은 Open/Completed, 제목, 설명, due/overdue를 명시한다.
- writable이며 완료를 지원하는 행의 완료 원은 18pt 실제 버튼이며 저장 중에는 같은 위치의
  spinner로 바꾸고 해당 행만 비활성화한다. read-only 또는 capability가 없는 field는 lock과
  `View only` 이유를 표시한다.
- 행을 누르면 520pt 이상 상세 sheet에서 최신 snapshot을 읽고 provider·account·list를
  읽기 전용으로, 제목·여러 줄 notes·기한 toggle/날짜/시간·완료를 편집 가능하게 표시한다.
  하단은 Delete, 여백, Cancel, Save 순서다. conflict에서는 draft를 유지한 채 Save/Delete를
  숨기고 `Reload Latest`와 Cancel만 남긴다.
- `All Lists`의 `+`는 먼저 writable provider list picker를 보여 주고, 특정 writable
  list 선택 중에는 그 list를 기본값으로 사용한다. 삭제 확인은 task 이름과
  provider·account·list, 연결 local task 보존을 함께 설명한다.
- 300pt inspector에서도 menu·검색·상태 control이 잘리지 않고 list/source/account와 task
  본문의 우선순위가 유지되어야 한다. 실제 keyboard·VoiceOver·Increase Contrast 판정은
  offscreen bitmap과 분리한다.

## 원본 일정 Editor

- toolbar plus와 `⌘N`은 580×700 sheet를 열고, 선택 일정 inspector의 `Edit Original Event`도 같은 editor를 사용한다.
- sheet는 title, writable calendar, location, time/all-day, time zone, **Original event notes** 순서로 배치한다. 원본 notes 아래에는 local Event Brief와 저장 위치가 다르다는 문구를 항상 표시한다.
- 종일 종료는 사람이 보는 포함 날짜로 표시하고, EventKit 배타 종료라는 설명을 붙인다.
- floating toggle 또는 IANA time zone 입력이 실제 draft에 적용되기 전에는 Save를 비활성화한다. Apply 뒤 `Keep local time`/`Keep instant`의 두 결과를 confirmation dialog에서 비교한다.
- DST gap·overlap처럼 local time이 존재하지 않거나 두 번 생기면 임의로 고르지 않고 field 가까이에 오류를 표시한다.
- local Brief가 연결된 일정도 calendar picker를 열어 두되, 이동·시간 의미·반복 변경은 impact review에서 확인한 뒤에만 write한다. linked delete는 첫 alert에서 바로 실행하지 않고 Phase 7C의 saved-link impact review와 별도 destructive Confirm으로 전환한다.
- read-only, attendee meeting/invitation은 inspector에서 원본 편집 대신 잠금 이유를 표시한다. 지원 가능한 반복 occurrence는 명시적 scope로 편집하고, detached·complex rule의 unsafe future/rule 변경만 Calendar.app으로 안내한다. local Brief 편집은 계속 가능하다.
- 저장 중에는 progress와 interactive-dismiss 차단을 사용한다. stale·identity 모호성은 write 전 복구 가능한 오류로 보여 준다. EventKit save 후 post-save occurrence를 확정하지 못한 부분 성공은 editor/review를 닫고 refresh한 뒤 “Do not retry·Calendar.app에서 확인”을 표시한다. local data는 보존하며 log·Undo를 만들지 않는다.
- 한 번에 하나의 editor만 허용하고 sheet가 열려 있으면 toolbar와 `⌘N`을 비활성화한다.

## Phase 8 source·role·permission badge

Source badge는 EventKit 계정 유형, 실제 calendar/source, 사용자가 정한 role과 원본 수정 가능 여부를 혼합하지 않고 함께 보여 준다.

역할:
- `Work`, `Personal`, `Family`, `Shared`, `Subscription`, `Other`
- subscribed/birthdays는 row가 없을 때 `Subscription`, 나머지 calendar는 용도를 추측하지 않고 `Other`
- 현재 source list에 calendar가 없고 exact explicit override도 없으면 이전 event/task의 account type snapshot으로 역할을 추측하지 않고 `Other`
- Sidebar role menu는 KaosCal local grouping만 바꾸며 Calendar.app의 이름·색·권한을 변경하지 않음

화면별 계층:
- Sidebar: calendar title 바로 아래 `Role · Source/Account · Editable|Read-only`, lock help에 상세 이유
- Agenda: 시간 · role · calendar를 항상 표시하고 source/account/restriction은 VoiceOver에 포함
- timed card: 58pt 이상에서 `Role · Calendar`; 더 낮은 card에서 생략된 role/source/permission/duplicate는 help·VoiceOver에 유지
- all-day card: 반복·duplicate·lock icon으로 밀도를 유지하고 role/source/restriction은 help·VoiceOver에 유지
- Inspector: role · account type · editable/restriction badge와 별도 `Calendar · Source` text, 정확한 read-only reason, duplicate candidate 목록
- Event editor calendar picker와 Task Center event/recovery source에도 현재 role을 포함

수정 불가 이유는 다음 우선순위의 typed projection을 사용한다.

1. Invitation
2. Meeting with attendees
3. Subscribed calendar
4. Birthdays calendar
5. macOS Calendar의 provider-reported read-only

모든 restriction 문구는 원본은 수정하지 못하더라도 local Event Brief는 editable임을 함께 알린다. Inspector와 AppState write preflight는 같은 typed restriction과 우선순위를 사용한다. Exchange/CalDAV/iCloud 공유 ACL의 구체 원인은 EventKit이 제공하지 않으면 추측하지 않는다.

## Calendar Set과 duplicate candidate

- Sidebar picker는 synthetic `All Calendars`, 사용자 이름의 saved Set, role별 `Smart Role Filters`를 분리한다. `⌃1`은 All, `⌃2`~`⌃9`는 정렬된 saved Set 중 앞의 8개를 선택한다.
- Settings의 `Calendar Sets` tab은 Set 생성·이름 변경·삭제·순서 변경과 account별 membership checkbox, `Include All`/`Remove All`, active Set 선택을 제공한다. 새 Set은 globally enabled calendar로 시작하거나 빈 Set으로 만들 수 있다.
- saved Set은 역할과 무관한 exact calendar identifier 조합이므로 서로 겹치거나 Work/Personal 등이 섞일 수 있다. 전역 `Enabled`가 master mask이며 calendar를 disable해도 membership은 지우지 않는다. `Block` availability 정책도 membership과 독립이다.
- 사라진 calendar membership은 unavailable row로 보존한다. 같은 이름의 calendar에 자동 연결하지 않으며 사용자가 `Replace…` 또는 `Remove`를 명시해야 한다. 권한 거부·loading·fetch failure에서는 missing으로 단정하지 않고 권한 있는 authoritative snapshot 뒤에만 unavailable row를 보여 준다.
- Set 변경 전 pending Event Brief notes를 flush하고, 새 set에서 숨겨지는 선택은 정리한다. 현재 선택은 재실행 뒤 복원하며 active saved Set 삭제나 잘못된 selection은 `All Calendars`로 fallback한다.
- duplicate badge는 다른 calendar의 정규화 title과 시간 범위가 보수적으로 같은 `Possible duplicate`임을 뜻한다. fetch 시 candidate index를 한 번 계산하고 각 card/Inspector는 event ID로 O(1) 조회한다. 확정 판정이 아니며 자동 merge·hide·delete하지 않는다.
- Inspector는 candidate의 시간, match 근거, role, calendar/account, permission을 보여 준다. candidate·relink 결과 또는 원본 저장 뒤 focus 대상이 normal filter 밖이면 저장된 Set 선택을 바꾸지 않고 해당 일정을 임시 reveal하며, 이미 보이는 일정에는 임시 banner를 만들지 않는다.

shared read-only Exchange의 실제 문구와 긴 source/role 조합, 고밀도 card의 시각 품질은 fixture 부재와 session lock 제한으로 live visual gate가 아직 미검증이다. 코드·fixture 투영을 이 gate의 통과로 해석하지 않는다.

## Phase 9 Local Data Settings

Settings의 `Local Data` 화면은 backup, restore, storage, privacy와 destructive reset을
한 화면에 분리된 group으로 보여 준다.

- `Manual Backup`은 `Export Backup…`으로 사용자가 `.zip` 위치를 고르게 한다. export
  중에는 spinner와 `Exporting…`을 표시하고 다른 local-data action을 잠근다.
- `Restore From Backup`은 파일 선택만으로 교체하지 않는다. 선택한 파일명, 현재 DB의
  자동 recovery backup이 먼저 만들어진다는 점, Calendar/Exchange 원본 불변을
  destructive confirmation에 함께 표시한다.
- `Storage`는 active SQLite의 실제 path를 selectable monospaced text로 표시하고
  `Show in Finder`를 제공한다.
- `What Is Included`는 Event Brief/task/role/calendar usage/saved Set·membership·selection/change history뿐 아니라 linked
  title/time/location/identifier와 original-notes change snapshot이 포함될 수 있음을
  밝힌다. 현재 UI는 complete calendar event record, account credential과 Exchange
  password를 전용 export 대상으로 삼지 않는다고 표시한다. KaosCal이 credential/token
  전용 필드나 attendee 전체 목록을 저장하지 않는다는 계약과 별개로, 사용자
  notes/tasks 본문은 redact하지 않으므로 그 안의 민감정보가 포함될 수 있다는 정확한
  경계는 같은 화면의 plaintext 경고와 backup 문서에서 보완한다.
- ZIP은 KaosCal이 암호화하지 않는 plaintext이며 사용자가 선택한 cloud folder에도
  그대로 저장된다는 경고를 action과 같은 화면에 둔다.
- `Reset Local Data…`는 red destructive hierarchy를 사용한다. 별도 sheet에서 정확히
  `RESET`을 입력해야 `Delete Local Data`가 활성화되고, 자동 recovery backup과
  Calendar/Exchange 원본 보존을 다시 설명한다.
- export/import/reset 성공 결과는 export 또는 recovery backup 경로를 selectable
  message로 남기고 사용자가 닫을 수 있게 한다. 실패 message는 validation/restore와
  active DB 유지·rollback 결과를 표시하지만 자동 backup 경로가 항상 포함되지는 않는다.
- import alert와 reset 확인 sheet는 사용자가 실행을 승인하면 닫힌 뒤 비동기 operation이
  계속된다. 진행 중에는 Settings의 다른 local-data action과 앱의 local/EventKit mutation
  진입을 막지만 Settings window 자체를 닫는 것은 operation 취소가 아니다. pending notes
  저장 실패나 진행 중 event mutation이 있으면 data operation을 시작하지 않고 해결할
  항목을 먼저 보여 준다.
- automatic backup retention/pruning control은 제공하지 않는다. `Backups`의 파일은
  사용자가 직접 관리한다.
- 정상 DB가 열리지 않은 global bootstrap failure에서 이 Settings 화면을 recovery로
  재사용하지 않는다. corrupt live DB recovery UI는 Phase 10이다.

archive 동작과 개인정보 계약은 [backup-restore.md](backup-restore.md)를 따른다.

## Phase 6 recurrence와 impact confirmation

Phase 6 confirmation은 반복 범위·calendar 이동·기존 시간 의미 변경과 linked local context가 받을 영향을 write 전에 읽는 작업 화면으로 구현되었다. 자동 gate는 통과했지만 실제 서명 창·`KAOS-TEST` 상호작용 통과를 의미하지 않는다.

- recurrence control과 review state를 수용하기 위해 editor 목표 크기는 640×760pt이며, 일반 field와 review를 동시에 편집하지 않고 한 sheet 안에서 단계적으로 전환한다.
- 새 일정에서는 기본 recurrence rule을 만들 수 있다. 기존 단일 일정을 series로 변환하는 control은 초기 Phase 6에서 제공하지 않으며 Calendar.app으로 안내한다.

반복 범위 control:
- 기존 반복 occurrence의 수정·이동·삭제에는 `이번 일정`과 `이번 이후`를 나란히 제공하고 기본 선택 없이 시작한다.
- 각 option 아래에 “한 occurrence만 변경되어 별도 일정이 될 수 있음” 또는 “선택한 occurrence와 이후 series에 영향”을 짧게 설명한다.
- `이번 일정`에서는 recurrence rule control을 잠그고 occurrence 상세만 바꾼다. rule 편집은 unlinked basic series의 `이번 이후`에서만 활성화한다.
- detached occurrence와 지원하지 않는 복잡한 규칙은 `이번 이후`와 recurrence rule control을 비활성화하고 Calendar.app 이유를 바로 표시하되 ordinary fields의 `이번 일정`은 열어 둔다. attendee meeting은 모든 원본 편집을 비활성화한다.

impact confirmation에 표시할 것:
- 작업 종류와 선택한 recurrence scope
- 기존/새 calendar와 source
- 기존/새 날짜·시각·all-day/floating/zoned 의미
- 함께 유지될 Event Brief notes와 Before/During/After task 수
- 현재 linked Event Brief의 notes 글자 수, section별 task 수·제목과 최근 change history
- series detach/split 가능성. 여러 linked context가 필요한 future scope는 preview 전에 차단
- 명확한 Confirm/Cancel

상태 규칙:
- preview를 만드는 동안 loading, validation 실패, stale refresh 필요를 구분한다.
- Cancel에는 EventKit 변경, local rebind, change log가 없어야 한다.
- confirm 뒤 저장 중에는 dismiss와 중복 명령을 막는다.
- EventKit만 성공하고 local transaction이 실패하면 “원본은 변경됨 / local 연결·기록 갱신 실패 / local notes와 tasks 보존”을 함께 보여 준다. post-save occurrence receipt가 불확실한 경우는 동일 write 재시도를 세션 상태로 차단하고 Calendar.app 확인을 요청한다.
- 초기 Phase 6의 linked `이번 이후`에는 Confirm을 제공하지 않는다. 후속 reconciliation을 열더라도 weak·ambiguous·missing이면 계속 Confirm을 제공하지 않는다.

## Phase 7C linked original delete review

- linked Delete의 첫 alert는 `Review Deletion Impact`만 제공하며 EventKit/SQLite를 바꾸지 않는다. editor 안의 final review는 원본 title/date/calendar, single 또는 `This occurrence only` scope, local notes 글자 수와 읽을 수 있는 일부 본문, section별 task 수·제목과 최근 history를 분리해 보여 준다.
- 원본 영역은 red destructive hierarchy, 보존되는 Local Event Brief 영역은 accent archive hierarchy를 사용한다. `Delete Original & Keep Brief`만 실제 destructive action이고 Back은 원래 editor로 돌아간다.
- final review에는 “원본만 삭제 / local Brief 유지 / Undo 없음 / 성공 뒤 Task Center에서 `Original deleted · Local Brief kept`로 접근”을 action 가까이에 명시한다.
- linked recurring은 `This event`만 열고 series가 계속되며 Exchange deletion exception이 생길 수 있음을 알린다. `This and future`, attendee/invitation과 read-only 원본에는 final Confirm을 제공하지 않는다.
- Confirm 직전 saved link가 stale이면 review를 닫고 다시 준비하게 한다. provider 성공 뒤 local finalize/receipt가 실패하면 editor/review를 닫아 Delete 재시도를 막고, 원본은 이미 삭제됐거나 삭제됐을 수 있음과 local notes/tasks 보존을 전역 오류로 보여 준다. 자동 원본 복원이나 Undo를 제안하지 않는다.
- Task Center row와 Local Event Briefs section은 일반 orphan과 deleted-original을 구분하되 `cancelled + orphaned`만으로 라벨을 만들지 않는다. current-link-generation unavailable `cancelled` log가 있고 이후 `(created_at, rowid)`상 더 최신 relink가 없을 때만 deleted-original style을 사용한다. deleted-original recovery sheet에서는 Relink와 local Brief 삭제를 제공하되 Keep as orphan은 다시 요구하지 않는다.

금지:
- 확인 전에 EventKit 변경
- 취소·실패·no-op 뒤 change log 기록
- context_id 재생성
- `이번 이후`를 작은 보조 문구로 숨기거나 default로 암묵 선택
- unsupported recurrence를 단순 규칙으로 덮어쓰거나 `이번 일정` ordinary-field patch에서 recurrenceRules를 다시 쓰기

## Phase 6 change history와 session Undo

- linked impact review에는 최근 변경을 시간 역순의 간결한 history로 표시한다. 현재 preview는 change type과 시각을 우선하며, move before/after와 recurrence scope를 상시 탐색하는 전체 history panel은 후속 polish다.
- history는 EventKit 원본을 자동 복원하는 control이 아니다. 영속 log의 `available` 표시만으로 Undo button을 재생성하지 않는다.
- Undo는 같은 실행 session에서 직전에 성공한 linked 비반복 `single` calendar/time 변경 한 건에만 잠시 제공한다.
- 다른 성공한 KaosCal write, 권한 철회, 앱 재실행 뒤에는 Undo를 숨긴다. 일반 EventKit refresh 뒤에는 자체 save 알림과 외부 변경을 구분할 수 없어 button이 남을 수 있지만, 실행 시 fresh stale check가 실패하면 원본과 local DB를 바꾸지 않고 이유를 설명한다.
- inspector의 `Undo Last Event Change`는 같은 strong event가 선택됐을 때만 나타나는 명시적 one-shot command다. 실행 중 control을 비활성화해 중복을 막고, provider fresh check를 통과해 성공하면 기존 history를 지우지 않고 `Restored` 항목을 추가한다.
- 반복 scope, detached occurrence, delete에는 Undo를 표시하지 않는다.

## 색과 밀도

- calendar color는 rail과 작은 badge에만 쓴다.
- 이벤트 카드 전체를 강한 캘린더 색으로 채우지 않는다.
- glass/blur는 sidebar, toolbar, popover에 제한한다.
- 긴 일정 제목에서도 레이아웃이 무너지지 않아야 한다.
- 고밀도 week view에서 겹침과 clipping을 피한다.
- 종일 일정, floating time, 고정 시간대 일정은 아이콘과 텍스트를 함께 사용해 구분한다.

## 초기 브랜드 방향

- 앱 아이콘: calendar grid·겹친 schedule blocks·apricot check를 결합한 KaosCal mark
- UI 기본 색: system background 위에 ink navy, muted slate, calendar accent만 사용
- 강조 색: calendar source color는 narrow rail과 badge에 제한
- 다크 모드: 같은 정보 계층을 유지하고 과한 neon/glass 효과를 피함

## 키보드 우선 작업

초기 단축키 후보:
- 새 일정: `⌘N` 구현
- 검색
- 오늘로 이동
- 이전/다음 기간
- Day/Week/Agenda 전환
- 선택 일정의 Event Brief로 focus 이동

## 접근성

- 색상만으로 상태를 전달하지 않는다.
- checkbox와 task row는 VoiceOver label을 가진다.
- source/read-only 상태는 텍스트로도 표시한다.
- hit target은 Mac 앱 기준에서 너무 작지 않게 유지한다.
- dynamic type 또는 accessibility font size에서 clipping을 점검한다.
