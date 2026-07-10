# Product Principles

## 제품 진실

KaosCal은 사용자를 대신해서 하루를 결정하는 AI 스케줄러가 아니다.
KaosCal은 사용자가 직접 일정을 관리할 때 준비물, 체크리스트, 메모, 후속 작업, 변경 기록, 캘린더 출처를 잃지 않게 해주는 macOS-first local-first calendar다.

## 한 줄 정의

일정의 시간뿐 아니라 그 일정에 딸린 맥락까지 보존하는 맥용 캘린더.

## v1 제품 약속

KaosCal v1은 macOS Calendar에 연결된 일정을 읽고 편집하며, 각 일정에 KaosCal만의 Event Brief를 로컬로 붙인다.
사용자는 병원, 회의, 출장, 행정 일정처럼 준비와 후속 작업이 필요한 일정을 더 안전하게 관리할 수 있어야 한다.

## 핵심 사용자

- Mac을 주 작업 기기로 쓰는 개인 사용자
- 회사/개인/가족 캘린더를 함께 쓰는 사용자
- 준비물과 후속 작업이 많은 일정을 자주 관리하는 사용자
- 투두 앱 전체는 부담스럽지만 일정에 붙은 체크리스트는 필요한 사용자
- 구독, 계정 가입, 서버 의존을 원하지 않는 사용자

## 제품 원칙

| 번호 | 원칙 | 개발 판단 기준 |
| --- | --- | --- |
| 1 | 사용자를 대신해서 일정을 결정하지 않는다. | 자동 재배치, 자동 수락, 자동 삭제는 v1에 넣지 않는다. |
| 2 | 사용자가 직접 바꿀 때 실수하지 않게 돕는다. | 이동, 취소, 삭제, 반복 변경 전 영향 범위를 보여준다. |
| 3 | 일정의 시간보다 맥락을 더 오래 보존한다. | 원본 일정이 삭제되어도 Event Brief는 즉시 삭제하지 않는다. |
| 4 | 캘린더 출처와 권한을 숨기지 않는다. | source, calendar role, editable/read-only 상태를 명확히 표시한다. |
| 5 | 할 일 앱이 아니라 event-centric workflow를 만든다. | 프로젝트, inbox, priority matrix는 v1에 넣지 않는다. |
| 6 | 구독 없이 살 수 있는 앱이어야 한다. | 서버 의존 기능은 v1 범위 밖으로 둔다. |
| 7 | 로컬 우선이다. | KaosCal 맥락 데이터는 이 Mac의 Application Support 아래 SQLite에 저장한다. |

## v1에 반드시 들어가는 것

- EventKit 권한 요청과 캘린더 목록 표시
- Week view, Day view, Agenda view의 기본 골격
- 일정 생성, 수정, 삭제의 기본 기능
- 오른쪽 Event Brief 패널
- Before, During, After 체크리스트
- KaosCal local notes
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
- 완전한 반복 일정 편집
- 프로젝트 관리 앱 또는 전체 투두 앱
- 서버 기반 KaosCal Cloud

## 핵심 데모

1. 사용자가 "치과 진료" 일정을 만든다.
2. Before 체크리스트에 "신분증", "보험 서류", "20분 전에 출발"을 추가한다.
3. After 체크리스트에 "약국 들르기", "다음 예약 잡기", "영수증 보관"을 추가한다.
4. 일정을 다음 주 월요일 10:00로 옮긴다.
5. KaosCal이 연결된 체크리스트, 메모, 후속 작업, 변경 기록이 함께 유지된다는 확인을 보여준다.
6. 이동 후에도 같은 Event Brief가 유지된다.
7. 일정 시간이 지나면 After Review에서 후속 작업만 따로 확인할 수 있다.
8. 상세에는 "Personal Google · Editable" 같은 출처와 권한이 명확히 보인다.

## 기능 판단 질문

새 기능을 넣기 전 아래 질문 중 하나라도 "아니오"라면 backlog로 보낸다.

- 병원 일정 데모를 더 완성도 있게 만드는가?
- Event Brief가 일정과 함께 안전하게 유지되는 데 기여하는가?
- 멀티 캘린더 출처와 권한을 더 명확하게 만드는가?
- local-first, no account, no subscription 포지션을 해치지 않는가?
- v1을 더 빨리 검증하게 만드는가?

## 브랜드 톤

KaosCal은 calendar chaos를 정리한다는 이름을 가지지만, UI와 문구는 장난스럽거나 공격적이면 안 된다.
제품 톤은 Calm Pro Calendar다. 차분하고 단단하며, 바쁜 사용자가 빠르게 읽고 판단할 수 있어야 한다.

