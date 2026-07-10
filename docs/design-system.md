# Design System

## 디자인 방향

KaosCal의 톤은 Calm Pro Calendar다.
바쁜 사용자가 하루의 일정을 빠르게 읽고, 어떤 일정에 어떤 맥락이 붙어 있는지 바로 판단할 수 있어야 한다.

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
- Day/Week/Agenda 중심
- Month는 v1에서 가볍게 시작하거나 후순위
- today indicator 명확히 표시

Event Brief Panel:
- 선택 일정의 title/time/source
- Before/During/After
- KaosCal notes
- change history 요약
- read-only 설명

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

