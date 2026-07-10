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
- mini month
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
- change history 요약은 Phase 6에서 추가
- read-only 설명

Task Center:
- sidebar 항목으로 열고 오늘·예정·완료를 빠르게 전환
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

### Phase 4 Task Center 실제 상호작용

- toolbar의 날짜 이동 control을 숨기고 `Task Center`와 local reload만 표시한다. 목록 기준일은 사용자가 이동한 calendar focused date가 아니라 현재 시각이다.
- 상단 segmented control로 Today/Upcoming/Completed를 전환한다.
- Today는 Overdue/Today/No date, Upcoming은 날짜별, Completed는 최근 완료 group으로 표시한다.
- row는 checkbox, inline title, task due, event section·원본 일정 범위·calendar/source 또는 `Personal · Local`, due edit, delete 순서다.
- personal quick-add는 제목·선택 due를 받는다. Upcoming에서는 내일 이후 due가 필수이고, due 변경 시 Today/Upcoming의 해당 목록으로 이동한다.
- due는 정렬·분류 metadata이며 reminder notification을 생성하지 않는다.
- event source를 누르면 target range를 불러온 뒤 강한 occurrence match만 Day 화면에서 연다. 못 찾으면 task는 유지하고 오류를 표시한다.
- loading, empty, query failed를 서로 다른 상태로 표시하며 실패에는 Retry를 제공한다.

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

## Move confirmation

Move confirmation은 공포를 주는 경고가 아니라 영향 범위 확인이다.

표시할 것:
- 기존 시간
- 새 시간
- 함께 유지될 항목: Before tasks, During tasks, After tasks, notes, change history
- confirm/cancel

금지:
- 확인 전에 EventKit 변경
- 취소 후 change log 기록
- context_id 재생성

## 색과 밀도

- calendar color는 rail과 작은 badge에만 쓴다.
- 이벤트 카드 전체를 강한 캘린더 색으로 채우지 않는다.
- glass/blur는 sidebar, toolbar, popover에 제한한다.
- 긴 일정 제목에서도 레이아웃이 무너지지 않아야 한다.
- 고밀도 week view에서 겹침과 clipping을 피한다.
- 종일 일정, floating time, 고정 시간대 일정은 아이콘과 텍스트를 함께 사용해 구분한다.

## 초기 브랜드 방향

- 앱 아이콘: 날짜 격자와 정리된 체크 표시를 결합한 단순한 KaosCal mark
- 기본 색: system background 위에 ink navy, muted slate, calendar accent만 사용
- 강조 색: calendar source color는 narrow rail과 badge에 제한
- 다크 모드: 같은 정보 계층을 유지하고 과한 neon/glass 효과를 피함

## 키보드 우선 작업

초기 단축키 후보:
- 새 일정
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
