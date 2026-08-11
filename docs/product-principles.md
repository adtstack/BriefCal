# Product Principles

## 제품 진실

BriefCal은 AI 기능을 제공하지 않는다. 사용자를 대신해 생성·요약·분류·추천하거나 하루를
결정하지 않는다.
BriefCal은 사용자가 직접 일정을 관리할 때 준비물, 체크리스트, 메모, 후속 작업, 변경 기록,
개인 할 일과 캘린더 출처를 잃지 않게 해주는 macOS-only local calendar다.

## 한 줄 정의

일정의 시간뿐 아니라 그 일정에 딸린 맥락까지 보존하는 맥용 캘린더.

## v1 제품 약속

BriefCal v1은 macOS Calendar에 연결된 일정을 읽고 편집하며, 각 일정에 BriefCal만의 Event Brief를 로컬로 붙인다. Day, Week, Agenda와 Task Center는 하나의 흐름으로 동작한다.
사용자는 병원, 회의, 출장, 행정 일정처럼 준비와 후속 작업이 필요한 일정을 더 안전하게 관리할 수 있어야 한다.

## 핵심 사용자

- Mac을 주 작업 기기로 쓰는 개인 사용자
- 회사/개인/가족 캘린더를 함께 쓰는 사용자
- 준비물과 후속 작업이 많은 일정을 자주 관리하는 사용자
- 일정에 붙은 체크리스트와 한눈에 보는 개인 할 일 목록이 모두 필요한 사용자
- 구독, 계정 가입, 서버 의존을 원하지 않는 사용자

## 제품 원칙

| 번호 | 원칙 | 개발 판단 기준 |
| --- | --- | --- |
| 1 | 사용자를 대신해서 일정을 결정하지 않는다. | 자동 재배치, 자동 수락, 자동 삭제는 v1에 넣지 않는다. |
| 2 | 사용자가 직접 바꿀 때 실수하지 않게 돕는다. | 이동, 취소, 삭제, 반복 변경 전 영향 범위를 보여준다. |
| 3 | 일정의 시간보다 맥락을 더 오래 보존한다. | 원본 일정이 삭제되어도 Event Brief는 즉시 삭제하지 않는다. |
| 4 | 캘린더 출처와 권한을 숨기지 않는다. | source, calendar role, editable/read-only 상태를 명확히 표시한다. |
| 5 | 일정 중심이되 할 일 목록을 숨기지 않는다. | Event task와 가벼운 Personal task를 Task Center에 모으되, 프로젝트·팀 협업·Kanban은 넣지 않는다. |
| 6 | 구독 없이 살 수 있는 앱이어야 한다. | BriefCal 계정·backend·cloud sync를 만들지 않는다. |
| 7 | 이 Mac이 유일한 실행·저장 경계다. | BriefCal 맥락 데이터와 설정은 이 Mac의 Application Support 아래 SQLite에만 저장한다. |
| 8 | AI를 제품에 넣지 않는다. | local/remote AI·LLM·ML SDK/API, 생성·요약·분류·추천·자동 배치를 도입하지 않는다. |
| 9 | 동기화는 기존 정본과 직접 연결한다. | Calendar는 EventKit, task는 사용자가 선택한 provider와 이 Mac이 직접 연결하며 BriefCal 중계 서버를 사용하지 않는다. |

## v1에 반드시 들어가는 것

- EventKit 권한 요청과 캘린더 목록 표시
- Day view, Week view, Agenda view의 완성된 공통 흐름
- 일정 생성, 수정, 삭제의 기본 기능
- 종일 일정, 시간대가 있는 일정, floating 일정의 표시와 안전한 편집
- 반복 occurrence 표시와 기본 반복 규칙 편집
- 오른쪽 Event Brief 패널
- Before, During, After 체크리스트
- BriefCal local notes
- Event task와 Personal task를 보여 주는 Task Center
- 일정 이동 시 연결 항목 이동 확인
- 일정 완료 후 After 작업 확인
- 캘린더 출처, 역할, 읽기 전용 상태 표시
- 로컬 SQLite 저장
- Export/Import backup

## v1에서 하지 않는 것

- AI 자동 스케줄링
- 팀 스케줄링 링크
- Google Calendar API 직접 OAuth 연동
- Microsoft Graph 직접 연동
- CalDAV/iCloud 직접 sync engine
- 모바일 앱
- Exchange Tasks 또는 Apple Reminders 직접 동기화
- 프로젝트 관리 앱, 팀 할 일, Kanban
- 초대 일정 RSVP·참석자·주최자 관리
- 서버 기반 BriefCal Cloud

이 목록은 동결된 v1의 제외 범위다. 동결 후 v2는 Event Brief task에 한해 Apple Reminders,
Google Tasks, Todoist와 Microsoft To Do provider 연결을 추가했다. Personal task는 계속
local-only이며, 후속 기능은 [상용 기능 로드맵](commercial-feature-roadmap.md)을 따른다.
AI·BriefCal Cloud·cross-device sync는
[ADR-019](adr/ADR-019-local-only-no-ai-no-product-cloud.md)에 따라 영구 제외한다.

## 핵심 데모

1. 사용자가 "치과 진료" 일정을 만든다.
2. Before 체크리스트에 "신분증", "보험 서류", "20분 전에 출발"을 추가한다.
3. After 체크리스트에 "약국 들르기", "다음 예약 잡기", "영수증 보관"을 추가한다.
4. 일정을 다음 주 월요일 10:00로 옮긴다.
5. BriefCal이 연결된 체크리스트, 메모, 후속 작업, 변경 기록이 함께 유지된다는 확인을 보여준다.
6. 이동 후에도 같은 Event Brief가 유지된다.
7. 일정 시간이 지나면 After Review에서 후속 작업만 따로 확인할 수 있다.
8. 상세에는 "Work Exchange · Editable" 같은 출처와 권한이 명확히 보인다.
9. Task Center에서 일정 작업과 개인 작업을 오늘 기준으로 함께 확인한다.

## 기능 판단 질문

새 기능을 넣기 전 아래 질문 중 하나라도 "아니오"라면 backlog로 보낸다.

- 병원 일정 데모를 더 완성도 있게 만드는가?
- Event Brief가 일정과 함께 안전하게 유지되는 데 기여하는가?
- 멀티 캘린더 출처와 권한을 더 명확하게 만드는가?
- Task Center에서 오늘 해야 할 일을 더 명확하게 만드는가?
- local-only, no account, no subscription 포지션과 ADR-019를 지키는가?
- 이 Mac 밖으로 BriefCal 소유 데이터를 자동 전송하거나 AI/cloud 의존성을 추가하지 않는가?
- v1을 더 빨리 검증하게 만드는가?

## 브랜드 톤

BriefCal은 calendar chaos를 정리한다는 이름을 가지지만, UI와 문구는 장난스럽거나 공격적이면 안 된다.
제품 톤은 Calm Pro Calendar다. BusyCal의 정보 밀도와 작업 흐름은 참고하되, 색·아이콘·레이아웃은 BriefCal 고유 디자인으로 만든다.
