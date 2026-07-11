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
│ Sets         │    14:00  ▌ Design Review            │ ☐ 신분증      │
│ All          │    15:00                             │ ☐ 보험 서류   │
│ Work Mode    │                                      │              │
└──────────────┴──────────────────────────────────────┴──────────────┘
```

## 3-pane 규칙

Sidebar:
- 고정 6×7 mini month 날짜 탐색기
- calendar list
- calendar sets
- visible filters

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
- event task에는 연결 일정의 시간과 source를 작게 표시
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
- read-only 또는 conflict는 icon/text로 표시하고 색상만으로 전달하지 않는다.

### Phase 2 실제 적용값

- 시간축: 24시간, 시간당 56pt, 30분 보조선
- 시간 gutter: 64pt
- Week 날짜 최소 너비: 112pt
- overlap column 최소 너비: 44pt; 더 좁아지면 날짜 열을 늘려 가로 scroll
- timed card: 최소 22pt, 3pt calendar rail, 5pt radius, 선택 시 2pt outline
- 높이 34pt 미만은 제목 중심, 34pt 이상은 시간, 58pt 이상은 calendar title까지 표시한다. 생략 정보는 tooltip과 VoiceOver label에 모두 남긴다.
- all-day row: 26pt, card 22pt. lane은 내용에 맞춰 늘지만 화면 높이의 35%·최대 240pt에서 내부 세로 scroll로 전환한다.
- 오늘 열은 약한 accent fill, 현재 시각은 red line과 dot으로 표시한다.
- calendar rail은 EventKit calendar의 실제 sRGB color snapshot을 사용한다. 색을 가져올 수 없을 때만 Exchange 공통 blue 또는 secondary gray를 fallback으로 쓴다.
- calendar role, 사용자 color override, calendar set은 Phase 8에서 추가한다.

### Mini month 실제 적용값

- Sidebar `List` 위에 고정하고 calendar 목록만 독립적으로 scroll한다.
- Sidebar 최소 폭 210pt에서 바깥 padding 12pt, 7열 간격 2pt, 날짜 최소 높이 24pt, 요일 header 최소 높이 16pt를 사용한다.
- 월은 항상 42개 civil day/6행이다. 현재 calendar의 첫 요일 순서, locale과 time zone을 사용하며 DST에서도 calendar day 연산으로 날짜를 만든다.
- 월 화살표는 본문 날짜를 바꾸지 않고 mini month만 탐색한다. 날짜 선택은 Day/Week/Agenda를 유지하고 Task Center에서는 Day로 이동한다.
- 다른 월을 둘러보는 중 toolbar Today 또는 이미 focused인 같은 날짜를 다시 선택해도 focused month로 복귀한다.
- focused date는 accent 원형 fill과 흰 숫자, today는 accent ring, focused+today는 흰 inset ring, 인접 월은 secondary와 낮은 opacity로 표시한다.
- 모든 날짜와 월 화살표는 `Button`이고 grid는 keyboard focus section이다. 날짜 접근성 label은 요일+전체 날짜, value는 focused/today/adjacent 상태, identifier는 calendar civil key를 쓴다.
- event dot은 42일 전체 fetch coverage를 보장할 때까지 표시하지 않는다.

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

## Source badge

Source badge는 사용자가 이 일정의 출처와 수정 가능 여부를 빠르게 이해하게 해야 한다.

예시:
- `Work Google · Editable`
- `Personal iCloud · Editable`
- `Holidays · Read-only`
- `Subscription · Read-only`

read-only 상세 문구:

```text
이 캘린더는 원본 일정을 수정할 수 없습니다.
KaosCal 체크리스트와 메모는 이 Mac에 저장할 수 있습니다.
```

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
