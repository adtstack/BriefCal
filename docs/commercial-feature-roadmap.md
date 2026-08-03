# 상용 기능 격차와 후속 구현 로드맵

> 상태: Active Product Specification
> 기준일: 2026-08-02, Asia/Seoul
> 적용 범위: v2 T0~T5, `v11_local_task_planning`과 Full Month MVP 이후의 후속 제품 작업
> 목적: 상용 캘린더와 비교해 부족한 기능을 숨기지 않고, KaosCal의 local-only 원칙을
> 지키는 구현 순서와 인수 기준을 고정한다.

## 1. 이 문서의 권한

이 문서는 후속 기능의 **우선순위와 제품 인수 기준**을 정한다. 현행 구현의 동작은
[제품·시스템 스펙](specification.md), 실제 통과 증거는
[Current Status](current-status.md)를 따른다. AI와 KaosCal Cloud를 영구 제외하고 이 Mac을
유일한 실행·로컬 데이터 경계로 두는 결정은
[ADR-019](adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md)를 따른다.

- `C0~C4`는 상용화 후속 순서다. 과거 코드 리뷰 심각도 `P0/P1/P2`, 기존 Phase 0~10,
  v2 provider 단계 `T0~T5`와 다른 번호 체계다.
- C1 항목은 제품 요구가 승인된 다음 구현 묶음이며 `COM-003` Full Month MVP는 구현과
  자동/offscreen 검증을 완료하고 live 대기 상태다.
- C2/C3 항목은 가치와 순서는 승인됐지만, 데이터·권한·EventKit 경계가 바뀌면 구현 전에
  ADR을 추가해야 한다.
- C4는 경쟁 제품에 있더라도 ADR-019에 따라 영구 제외한다.
- 한 단계의 모든 기능을 한 번에 출시할 필요는 없지만, 같은 단계에서는 문서의 위쪽
  항목을 먼저 검토한다.

## 2. 제품 위치와 비교 결론

KaosCal의 현재 강점은 다음과 같다.

- exact membership을 갖는 이름 있는 Calendar Set과 role/source/permission 설명
- 일정 제목과 시간을 읽는 4~6주 Full Month, multi-day 주별 segment와 overflow
- 원본 일정이 이동·삭제돼도 notes와 Before/During/After를 조용히 버리지 않는 Event Brief
- Apple Reminders, Google Tasks, Todoist, Microsoft To Do를 구분하는 task provider 경계
- remote/local conflict, missing, bounded pending retry, exact relink와 local-only 복구
- 원본 일정과 로컬 맥락을 분리한 안전한 편집·삭제·backup/reset
- KaosCal 계정·서버 없이 이 Mac에서 EventKit과 선택한 task provider로 직접 연결하는 sync

반면 현재 제품은 Fantastical, Apple Calendar, Google Calendar, Outlook 같은 범용
캘린더를 완전히 대체하기보다 **Calendar.app 위에서 일정 맥락과 작업을 보존하는
macOS-first 실행 허브**에 가깝다. Full Month MVP는 구현했지만, 상용 대체재로 표현하려면
알림, 일정 검색, 빠른 생성과 회의 진입 같은 일상 기본기를 더 채워야 한다.

시장 비교는 2026-07-18에 공식 제품 문서를 기준으로 확인했다.

| 시장 기능 | 공식 비교 예 | KaosCal 현재 상태 | 방향 |
| --- | --- | --- | --- |
| 빠른 생성, 템플릿 | [Fantastical 기능](https://flexibits.com/fantastical?force_isolation=true) | 구조화 editor만 있음 | C1에서 구조화 Quick Add·local template 구현 |
| 전체 Month/Quarter/Year | [Fantastical 기능](https://flexibits.com/fantastical?force_isolation=true) | Month MVP 구현·자동/offscreen 검증 완료·live 대기, Quarter/Year 없음 | Month live gate를 닫고 Quarter/Year는 C3 재평가 |
| 일정·task 알림 | [Apple Calendar 알림](https://support.apple.com/guide/calendar/icl1012/mac) | task due는 분류이며 notification이 아님 | C1 |
| 초대 응답·새 시간 제안 | [Apple Calendar 초대](https://support.apple.com/guide/calendar/icl1019/mac) | invitation/attendee 원본 변경을 Calendar.app으로 위임 | C2에서 상태·왕복 UX, 직접 RSVP는 C4 |
| 첨부파일·URL | [Apple Calendar 첨부](https://support.apple.com/guide/calendar/icl58679aba2/mac) | T5 reference는 별도 URL metadata | C2에서 안전한 표시·열기부터 구현 |
| 예약 페이지·일정 투표 | [Google 예약 일정](https://support.google.com/calendar/answer/16287054), [Outlook Scheduling Poll](https://support.microsoft.com/outlook/find-the-best-meeting-time-for-everyone-with-outlook-scheduling-poll) | blocking interval만 계산하며 외부 scheduling 없음 | C4 영구 제외 |
| 다중 시간대·회의 연결 | [Notion Calendar 시간대](https://www.notion.com/help/time-zones), [Notion Calendar 연결](https://www.notion.com/help/notion-calendar-connections) | 시간 의미는 보존하지만 동시 다중 zone·conference join 없음 | C1/C2 |
| task time blocking | [Akiflow task 기능](https://product.akiflow.com/help/articles/0006630-task-features) | provider task drag→event block과 Event Task 연결 구현 / live 대기 | 실제 계정·부분 성공 gate 뒤 확장 |

KaosCal은 AI나 자체 cloud 기능의 개수로 경쟁하지 않는다. 이 Mac의 Calendar/Event Brief/
Task Center 완성도, 설명 가능한 충돌 복구와 macOS·provider 직접 동기화 품질로 경쟁한다.

### 현재 진행 중인 Tasks 실행 트랙

상용 캘린더 기본기 `C0~C4`와 별개로, 사용자가 승인한 Tasks 완성 트랙은 아래 순서를 따른다.

1. **구현 / live 대기:** 네 provider의 capability-aware 생성·완료·편집·삭제와 일괄 완료,
   Apple 목록/account 이동과 Todoist project/section 이동·일괄 이동, version-aware session Undo, 지원되는 원본 열기, keyboard focus
   및 Microsoft To Do reminder
2. **구현 / live 대기:** 기존 provider task와 Event Brief 연결, task→calendar time block, 연결
   일정 이동·삭제 impact preview와 Calendar Set task filter
3. **구현 / live 대기:** Today/Upcoming/Overdue/No Date/Completed, 날짜/list grouping, 저장 local
   filter와 Calendar+Tasks 통합 검색, due와 예상/실제 실행 시간 분리
4. **구현 / live 대기:** capability 기반 priority/importance와 local recurrence/checklist.
   provider가 의미를 보존하지 못하는 반복·하위 작업은 local overlay로만 유지
5. **코드 구현 / 실제 계정 gate 대기:** durable Event Brief mutation queue, bounded retry/cancel,
   last sync, conflict/missing recovery와 직접 provider mutation의 draft 보존·명시적 재시도

provider 간 자동 복제, AI, KaosCal Cloud와 기기 간 KaosCal 데이터 동기화는 이 트랙에도
포함하지 않는다.

## 3. 우선순위 단계

### C0 — 현재 구현의 상용화 증거 닫기

C0는 새 기능 단계가 아니다. C1을 크게 확장하기 전에 현재 T0~T5와 v10의 실제 동작을
확정하는 출시 차단선이다.

1. 작성된 최신 task provider 회귀 테스트를 실행하고 unexpected failure/skip을 0으로 만든다.
2. Apple Reminders, Google Tasks, Todoist, Microsoft To Do에서 비민감 fixture로
   create/update/complete/delete/relink/local-only/restart/retry limit를 확인한다.
3. Calendar Set CRUD·overlap·mixed role·missing Replace와 재실행 복원을 실제 계정에서 확인한다.
4. 실제 창 keyboard, focus, 긴 문구, Increase Contrast와 VoiceOver를 확인한다.
5. exact Release의 Developer ID, notarization, package, clean-user, license/support/privacy
   gate를 닫는다.

C0 통과 전에도 C1 코드를 개발할 수 있지만, C0 미완료 상태에서 public beta-ready 또는
상용 지원 완료를 선언해서는 안 된다.

### C1 — 일상 캘린더 기본기

C1은 다음 구현 묶음이다. 각 항목은 [제품·시스템 스펙](specification.md)의 `COM-*`
요구사항과 같은 ID를 사용한다. `COM-003`은 구현과 자동 gate를 통과했지만 live gate가 남아 있으며,
나머지 항목의 상태를 함께 완료로 승격하지 않는다.

#### COM-001 — 일정·Task 알림

- 상태: 설계 승인 / 구현 대기
- 사용자는 일정과 local task에 명시적으로 알림을 설정·변경·해제할 수 있어야 한다.
- provider due, Task Center section 기본 due와 notification opt-in을 같은 의미로 취급하면
  안 된다.
- 권한 거부, 삭제, 완료, due 변경과 재실행 뒤에도 중복 알림을 만들면 안 된다.
- 알림을 열면 exact event occurrence 또는 typed task로 이동해야 하며 찾지 못하면 원본이나
  task를 자동 재생성하지 않는다.
- remote provider의 reminder write는 capability와 사용자 승인이 확인되기 전에는 local
  notification을 넘어 확장하지 않는다.

#### COM-002 — 전체 일정 검색

- 상태: 설계 승인 / 구현 대기
- 제목, 장소, calendar/source와 날짜 범위로 일정을 검색하고 exact 결과를 선택해
  Day/Week/Agenda의 해당 occurrence로 이동할 수 있어야 한다.
- 검색한 EventKit 범위를 UI에 표시하고, bounded 결과를 전체 기록 검색처럼 표현하면 안 된다.
- attendee 전체 목록이나 원본 notes 전문을 검색 목적으로 SQLite에 복제하지 않는다.
- 선택 Calendar Set 밖의 결과는 저장 Set을 바꾸지 않는 temporary reveal 규칙을 재사용한다.
- 빠른 입력, 취소, 오래된 비동기 결과와 권한 철회를 자동 검증한다.

#### COM-003 — 전체 Month 보기

- 상태: 구현·자동/offscreen 검증 완료 / live 대기
- mini month와 별도로 일정 제목과 시간 정보를 보여 주는 4~6주의 본문 Month를 구현했다.
  locale과 first weekday를 따르고 인접 월을 포함한 완전한 주만 표시한다.
- all-day와 timed multi-day는 배타 종료를 지켜 주 경계마다 이어지는 segment로 나눈다.
  셀에 들어가지 않는 일정은 `+N more`와 날짜별 popover로 열며, event 선택은 기존
  Inspector, 날짜 동작은 해당 Day로 이어진다.
- `global Enabled ∩ selected Calendar Set`을 적용하되 raw fetch, recovery와 availability
  blocking을 줄이지 않는다. 이전·다음은 달 단위로 이동하고 오래된 비동기 조회가 현재
  월을 덮지 않는 기존 fetch 경계를 재사용한다.
- 상단 `Day / Week / Month / Agenda` 전환기, `⌘1`~`⌘5`, 날짜 방향키 focus와
  VoiceOver 의미를 구현했다. 312-test 전체 회귀와 560×520 offscreen render는 통과했으며
  실제 창의 고밀도·keyboard·VoiceOver는 통과 근거가 생길 때까지 pending이다.
- 첫 버전에는 일정 drag resize/move, Quarter/Year, 전체 일정 검색, 날짜별 Day Summary와
  Quick Add/template을 포함하지 않는다.

#### COM-004 — Quick Add와 Template

- 상태: 설계 승인 / 구현 대기
- 전역 또는 앱 내부 단축키로 일정과 task의 빠른 생성 흐름을 열 수 있어야 한다.
- 구조화 입력과 이 Mac에 저장하는 deterministic 사용자 template만 제공한다.
- AI·LLM·machine-learning inference, 자연어 생성·분류·요약·일정 추론은 구현하지 않는다.
- template은 credential, account identity나 과거 attendee를 의도치 않게 복제하면 안 된다.

#### COM-005 — 회의 링크 감지와 Join

- 상태: 설계 승인 / 구현 대기
- 현재 EventKit snapshot의 URL, location 또는 notes에 있는 지원 가능한 HTTPS 회의 링크를
  감지해 Details/Agenda에서 한 번에 열 수 있어야 한다.
- 읽기 단계에서 event notes나 URL을 SQLite/backup에 새 전용 원문으로 복제하지 않는다.
- 여러 후보, 유효하지 않은 URL과 비HTTPS 링크는 자동 실행하지 않고 사용자가 선택하게 한다.
- Google Meet, Microsoft Teams, Zoom 등 서비스 이름은 표시 보조값일 뿐 provider identity나
  안전 판정으로 사용하지 않는다.

### C2 — Mac 작업 흐름과 수동 계획

#### COM-006 — 수동 Task time blocking

- 상태: 구현 / live 대기
- 사용자가 task에 예상 소요 시간을 지정하고 캘린더의 빈 시간에 명시적으로 배치할 수
  있어야 한다.
- 자동 재배치·자동 우선순위 결정은 하지 않는다.
- 현재 구현은 명시적 drag에서 15분 단위·기본 1시간 EventKit event와 During task를 만들고
  exact provider binding을 연결한다. 자동 재배치나 task 완료 전파는 하지 않는다.
- writable Calendar Set destination 부재, provider/local 부분 성공과 event 삭제·이동 영향은
  실제 계정 gate에서 검증하고 조용한 task 삭제로 보정하지 않는다.

#### COM-007 — Command Bar와 menu bar

- 상태: 로드맵 승인 / 설계 대기
- keyboard-first로 Today 이동, 일정 검색, Quick Add, Calendar Set 전환과 다음 일정 확인을
  제공한다.
- menu bar 화면은 별도 데이터 정본을 만들지 않고 AppState projection을 사용해야 한다.
- 좁은 폭, 다중 Space, 앱 비활성 상태와 VoiceOver focus를 live 검증한다.

#### COM-008 — 다중 시간대 비교

- 상태: 로드맵 승인 / 설계 대기
- Day/Week에서 primary zone과 사용자가 고른 secondary zone을 동시에 읽을 수 있어야 한다.
- `floating`, `allDay`, `zoned` 의미를 바꾸거나 event를 저장하지 않고 display projection만
  변경해야 한다.
- DST 전환과 zone label 중복·약어 충돌을 테스트한다.

#### COM-009 — Calendar Set 로컬 자동 전환

- 상태: 로드맵 승인 / ADR 대기
- 사용자가 명시한 시간 규칙으로 saved Set을 이 Mac에서 자동 전환할 수 있다.
- cloud/device sync는 요구하지 않는다. 위치 기반 전환은 별도 위치 권한·privacy ADR과
  명시적 opt-in 없이는 구현하지 않는다.
- 편집 중, unsaved notes, recovery sheet와 temporary reveal을 자동 전환이 방해하면 안 된다.
- 자동 전환 이유와 이전 Set으로 돌아가는 동작을 사용자에게 보여 줘야 한다.

#### COM-010 — 일정 URL·첨부·초대 왕복

- 상태: 로드맵 승인 / 설계 대기
- EventKit이 안전하게 제공하는 URL, attachment metadata, organizer와 현재 응답 상태를
  Details에서 읽을 수 있어야 한다.
- 지원되지 않는 attachment write, RSVP와 attendee 변경은 비활성 control로 흉내 내지 않고
  exact event를 Calendar.app에서 여는 동작과 제한 설명을 제공한다.
- attachment 본문과 attendee 전체 목록은 KaosCal SQLite/backup에 전용 복제하지 않는다.

#### COM-011 — Task 계획 기본값 확장

- 상태: 구현 / live 대기
- local task에 예상/실제 duration, 반복과 명시적 priority, 중요 표시와 checklist를 제공한다.
- provider가 의미를 보존하지 못하면 조용히 필드를 버리지 않고 local-only 또는 설명 가능한
  capability 제한을 사용한다.
- 반복 완료는 다음 local occurrence를 만들고 checklist를 초기 상태로 복사한다. 프로젝트·팀
  공유·Kanban과 provider 반복 규칙 강제 변환은 포함하지 않는다.

### C3 — 선택적 확장과 호환성

#### COM-012 — Reference 로컬 정리 강화

- 상태: 로드맵 승인 / 설계 대기
- T5에 이미 저장된 URL, 사용자 제목, provider와 상태 metadata의 local search·정렬·grouping을
  검토한다.
- remote metadata preview, background crawler, 외부 문서 본문 저장, 양방향 notes sync와
  task 자동 변환은 포함하지 않는다.

#### COM-013 — 구버전 backup importer

- 상태: 로드맵 승인 / ADR 대기
- 지원하기로 선택한 과거 KaosCal archive를 격리된 staging DB에서 검증·migration한 뒤 현재
  schema backup으로 변환해야 한다.
- preflight 전에 active DB를 건드리지 않고 실패 시 원본 archive와 active DB를 보존한다.
- 임의 SQLite 복구, 미래 schema downgrade와 record-level merge는 포함하지 않는다.

#### COM-014 — Quarter/Year와 로컬 요약

- 상태: 재평가 대기
- Month와 검색의 실제 사용성 결과 뒤에만 Quarter/Year와 현재 EventKit snapshot 기반 로컬
  시간 요약을 각각 독립 제안으로 평가한다.
- telemetry, remote analytics, weather API, AI summary와 background content upload를
  도입하지 않는다.

### C4 — 영구 제외

다음은 상용 제품에 존재해도 ADR-019의 local-only/no-account/no-subscription 경계에 따라
구현하거나 재평가하지 않는다.

- AI/LLM/ML 기반 생성·요약·분류·추천·검색·자동 스케줄링·자동 재배치·수락·삭제
- 외부 예약 페이지, 팀 scheduling link와 meeting poll 서버
- KaosCal 계정·backend·cloud database·sync relay·remote config·telemetry/behavior analytics
- 모바일·웹 companion과 Event Brief/Task/Calendar Set cloud/device sync
- Google/Microsoft/CalDAV/iCloud Calendar 직접 sync engine
- RSVP, 참석자·주최자 편집과 delegate/shared calendar 권한 관리
- 프로젝트·팀 task, Kanban과 조직용 universal inbox
- 외부 notes 본문 양방향 sync와 reference의 task 자동 변환
- backup record merge, 미래 schema downgrade와 backup 없는 destructive reset

이 경계를 바꾸려면 ADR-019를 supersede하는 새 ADR이 필요하다. 일반 backlog나 경쟁 제품
비교만으로 C4 항목을 다시 열지 않는다.

## 4. 상용 출시 공통 게이트

모든 C1~C3 기능은 다음 공통 기준을 따른다.

1. 요구사항 ID와 실패 경계를 코드보다 먼저 갱신한다.
2. local-only와 provider 미연결 흐름을 회귀시키지 않는다.
3. 기능은 이 Mac에서 실행되고 KaosCal 소유 데이터를 이 Mac 밖으로 자동 전송하면 안 된다.
4. AI SDK/API, KaosCal backend endpoint, telemetry와 remote feature flag를 추가하면 안 된다.
5. EventKit/provider 원본 write는 권한·identity·scope 확인과 사용자 승인 뒤에만 수행한다.
6. 정상·취소·권한 거부·재실행·stale result·부분 성공을 자동 테스트한다.
7. 실제 계정이나 macOS 기능을 주장하면 exact signed artifact, 비민감 fixture와 cleanup을
   live 증거로 남긴다.
8. keyboard, VoiceOver, Increase Contrast, 긴 localized copy와 최소 창 크기를 확인한다.
9. backup schema/reset 대상이 바뀌면 migration·backup·restore·reset을 같은 변경에서 갱신한다.
10. public 또는 paid 배포는 Developer ID, notarization, package, license/EULA,
   support/privacy/security 연락처와 clean-user 설치 gate를 모두 통과해야 한다.

## 5. 작업 선택 규칙

새 작업을 시작할 때 다음 순서로 판단한다.

1. C0의 실패 또는 실제 사용자 검증에서 나온 데이터 손실·잘못된 원격 write 문제
2. 현재 C1에서 가장 위에 있는 미구현 요구사항
3. 이미 시작한 C1 기능의 접근성·복구·문서·live gate
4. C2의 ADR/feasibility 작업
5. C3 재평가

버그와 안전 문제는 단계 순서보다 우선한다. 다만 실제 실패 증거가 없는 C2/C3 기능을 이유로
C1의 기본기를 건너뛰지 않는다.
