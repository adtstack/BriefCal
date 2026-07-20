# ADR-019: 이 Mac에서만 실행하는 무AI·무KaosCal Cloud 제품 경계

> 상태: Accepted
> 날짜: 2026-07-18
> 관계: ADR-001, ADR-005, ADR-015, ADR-016, ADR-018, v2 T0~T5

## 결정

KaosCal의 제품 기능과 KaosCal 소유 데이터는 **이 Mac을 유일한 실행·저장 경계**로
유지한다.

1. AI, LLM, machine-learning inference와 AI SDK/API를 제품 기능으로 도입하지 않는다.
   local model과 remote model을 구분하지 않고 모두 제외한다.
2. KaosCal 계정, KaosCal backend, cloud database, sync relay, webhook server, remote config,
   hosted scheduling page와 server-side automation을 운영하지 않는다.
3. Event Brief, local notes/tasks, lifecycle, change history, calendar role/usage, saved Calendar
   Set, 설정과 recovery metadata는 이 Mac의 SQLite/Application Support에만 저장한다.
4. 위 KaosCal 소유 데이터를 다른 Mac, 모바일, 웹 또는 KaosCal 서버로 자동 동기화하지
   않는다. 사용자가 명시적으로 만든 plaintext ZIP export/import만 기기 이전 경로다.
5. 캘린더 동기화는 macOS Internet Accounts와 EventKit이 담당한다. KaosCal은 Calendar
   provider의 sync engine이나 중계 서버가 되지 않는다.
6. 사용자가 명시적으로 연결한 Apple Reminders, Google Tasks, Todoist와 Microsoft To Do
   adapter는 이 Mac에서 provider로 직접 통신하는 **task 동기화 client**로 유지할 수 있다.
   credential은 Keychain에만 저장하고 KaosCal 서버를 경유하지 않는다.
7. 검색, Month, 알림, template, Command Bar, time blocking과 Calendar Set 자동 전환 같은
   후속 기능은 로컬 규칙과 macOS framework로 구현한다. AI 추론이나 KaosCal cloud를 전제로
   기능 품질을 보완하지 않는다.

이 결정에서 `local-only`는 인터넷 연결을 전면 금지한다는 뜻이 아니다. 원본 Calendar와
사용자가 고른 task provider는 각 서비스의 정책에 따라 네트워크 동기화될 수 있다.
KaosCal 고유 맥락과 판단을 KaosCal 소유 서버로 보내거나 다른 기기에 자동 복제하지
않는다는 뜻이다.

## 근거

- KaosCal의 차별점은 사용자를 대신한 추론이 아니라 일정 원본과 Event Brief를 안전하게
  연결하고 맥락을 오래 보존하는 것이다.
- AI 기능은 오판 설명, 데이터 전송, 비용, 모델 변경과 재현성 문제를 제품 핵심에 추가한다.
- 자체 cloud는 계정·인증·서버 보안·운영·삭제 요청·장애·구독 비용을 만들고, 구독 없음과
  local ownership이라는 제품 약속을 약화한다.
- macOS EventKit과 provider별 client sync를 사용하면 Calendar/Tasks의 기존 정본을 유지하면서
  KaosCal이 별도 sync server를 운영하지 않아도 된다.
- 이 Mac 하나에서 검색·알림·Month·빠른 입력·task planning을 완성하는 편이 범용 cloud
  협업 기능을 넓히는 것보다 현재 사용자에게 직접적인 가치를 준다.

## 허용하는 외부 경계

- macOS EventKit과 사용자가 System Settings/Internet Accounts에 구성한 Calendar provider
- 사용자가 Settings에서 명시적으로 연결한 task provider와 provider OAuth endpoint
- 사용자가 클릭해 여는 HTTPS conference/reference URL
- Developer ID/notarization, 사용자가 시작한 update/download와 결제·license 전달처럼
  배포에 필요한 최소 외부 서비스. 이 경계는 Calendar/Event Brief/task 본문을 전송하면
  안 되며 앱의 핵심 기능은 일시적 서비스 장애 중에도 가능한 범위에서 계속 동작해야 한다.
- 사용자가 직접 선택한 외장·network/cloud folder. KaosCal은 그 위치를 sync 대상으로
  관리하지 않으며 plaintext backup의 제3자 전송 가능성을 명확히 알려야 한다.

## 금지하는 구현

- AI 자연어 생성·요약·분류·우선순위·일정 추천·자동 재배치
- AI를 이용한 event/task/reference 내용 분석과 embedding/vector database
- KaosCal 계정, telemetry/behavior analytics, remote feature flag와 background content upload
- KaosCal 소유 Event Brief/Task/Calendar Set cloud sync와 모바일·웹 companion
- webhook 수신이나 scheduling link를 위한 KaosCal hosted server
- cloud가 없으면 사용할 수 없는 핵심 캘린더·task workflow

## 결과

- `COM-004` Quick Add는 구조화 입력과 deterministic template만 제공한다. 자연어 AI/parser는
  요구사항에서 제거한다.
- C4의 AI/KaosCal Cloud 항목은 재평가 가능한 보류가 아니라 영구 제외다. 이 경계를
  바꾸려면 ADR-019를 supersede하는 새 ADR과 데이터 처리·비용·철회 계획이 필요하다.
- local Calendar Set과 KaosCal 맥락의 cross-device sync는 구현하지 않는다.
- provider sync 화면은 “KaosCal Cloud sync”가 아니라 이 Mac과 사용자가 선택한 provider
  사이의 직접 연결임을 설명해야 한다.
- Privacy, Security, Distribution과 user-facing copy는 서버 없음과 제3자 provider sync를
  구분해야 한다.

## 인수 기준

1. product/release dependency audit에 AI SDK, analytics SDK, KaosCal backend endpoint와
   background upload가 없어야 한다.
2. network가 끊겨도 local DB, Event Brief, Personal task, Calendar Set과 이미 읽은 snapshot을
   가능한 범위에서 사용할 수 있어야 한다.
3. provider 연결 없이도 local-only 회귀가 모두 통과해야 한다.
4. SQLite/ZIP/log에 OAuth token을 넣지 않고 provider 통신이 KaosCal 중계 endpoint를
   사용하지 않아야 한다.
5. 새 기능 스펙은 local execution/data ownership을 명시하고 AI/cloud 의존성을 추가하지
   않았음을 검토해야 한다.
