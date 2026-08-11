# T2 — Google Tasks + Todoist

> 상태: implemented / Google Cloud configured / live pending — OAuth·multi-provider coordinator·Settings destination까지 구현, provider별 실계정 gate 대기
> 선행: T0, T1에서 확정한 destination·sync·conflict 계약

## 목표

OAuth 기반 provider 두 종류를 같은 계정·Keychain·동기화 경계로 연결하되, provider의
고유 기능을 BriefCal에 복제하지 않는다. T2는 Google Tasks와 Todoist를 하나의 거대한
통합으로 출시하지 않고 **T2-Google**과 **T2-Todoist** 두 독립 gate로 운영한다.

## 공통 OAuth 계층

- authorization code + PKCE 흐름을 사용한다.
- access/refresh token은 Keychain에 저장하고 SQLite·로그·backup에 넣지 않는다.
- redirect, scope, account display name, revoke 결과를 provider별로 보존한다.
- 계정 연결 해제 시 token revoke를 시도하고 연결 metadata/cache 삭제를 확인받는다.
- token 만료와 scope 부족은 local-only fallback과 `Needs attention`으로 구분한다.

### 현재 구현된 기반

- `v5_oauth_task_providers` migration은 provider account를
  `(provider, account_key)`로 식별한다. 따라서 Google과 Todoist가 우연히 같은
  외부 subject 값을 사용해도 계정이 합쳐지지 않는다.
- token은 `KeychainOAuthCredentialStore`에만 저장한다. SQLite에는 account의
  display metadata와 task binding만 보관하며, OAuth token은 backup/export 대상이 아니다.
- legacy provider item의 cached notes는 v5 migration에서 비우고 이후에도 SQLite에
  다시 저장하지 않는다. remote description의 양방향 projection은 해당 local model과
  backup 정책을 함께 설계한 뒤 별도 gate로 연다.
- reset은 provider account/item/binding/destination뿐 아니라 cursor와 대기 작업도
  지운다. Keychain credential 삭제는 provider별 **Disconnect** 확인 흐름에서만 수행한다.
- authorization URL은 PKCE S256과 state를 포함한다. Google Desktop client credential은
  개발자/CI의 빌드 입력으로만 받고 최종 사용자에게 입력받지 않는다.
  Google은 `http://127.0.0.1:<port>` loopback redirect만, Todoist는 HTTPS 또는
  localhost test redirect만 허용한다.
- authorization code 및 refresh-token 교환 request는 Google의
  `oauth2.googleapis.com/token`과 Todoist의 `api.todoist.com/oauth/access_token`
  endpoint에 대해 form-encoded PKCE request로 생성한다. Google은 등록된 Desktop client
  credential을 token/refresh request에 함께 보내고 Todoist public-client 흐름에는
  `client_secret`을 넣지 않는다.
- Google Tasks REST v1 request builder는 list/get/create/update/delete와 ETag
  `If-Match` write를, Todoist API v1 builder는 project/section routing과
  create/update/move/close/reopen/delete를 각각 계약 테스트로 고정한다.
- 기존 Apple 전용 coordinator는 provider account가 가리키는 adapter로 create/update/delete를
  route한다. Settings Picker는 `(provider, account, list)` 복합 key로 선택하므로 서로 다른
  provider의 같은 raw list ID가 섞이지 않는다.
- Google task list의 `nextPageToken`, Todoist project/section의 cursor page를 끝까지
  순회한다. Todoist Settings destination은 Inbox/project뿐 아니라 section도 표시한다.
- Todoist는 최근 90일의 completion-date archive를 같은 project/section으로 bounded 조회해
  `Completed` projection에 포함한다. active task GET이 404인 경우에도 같은 archive를 확인해
  외부 완료를 `missing`으로 잘못 처리하지 않는다.
  archive에 없는 task는 삭제와 장기 보관 완료를 확정할 수 없으므로 기존처럼 `missing`으로
  남기며 local task를 자동 삭제하지 않는다.
- Google은 포트 없는 `http://127.0.0.1` base에서 먼저 임의 가용 포트를 확보하고, 실제
  `http://127.0.0.1:<port>`를 authorization과 token exchange에 동일하게 전달한다. callback의
  state와 path를 확인하고 중복 callback은 한 번만 완료하며, callback이 없으면 5분 뒤
  `Connecting`을 종료한다. 고정 포트를 사용하는 Todoist/Microsoft 구성에는 이 규칙을
  적용하지 않는다.
- Google token response에 `openid`와
  `https://www.googleapis.com/auth/tasks`가 모두 승인된 경우에만 account identity를 조회하고
  Keychain에 저장한다. 일부 scope가 빠지면 account metadata를 만들지 않고 재연결 가능한
  오류를 남긴다. OAuth account는 Google `sub`, Todoist user ID로 식별하며 email을 account
  key로 쓰지 않는다.
- disconnect는 BriefCal Keychain credential 및 local provider metadata/destination/binding을
  삭제하고 local event task는 유지한다. public desktop client는 provider별 server-side revoke
  endpoint를 안전하게 일반화할 수 없으므로, provider consent page revoke는 별도 사용자
  안내/live gate로 남긴다.
- OAuth session은 만료 시각 전의 401에도 refresh token으로 단 한 번만 재발급·원 요청
  재시도를 수행한다. 429는 retry hint와 함께 사용자 오류로 남기며 무한 background retry를
  하지 않는다.

### 배포 전 등록값

아래 OAuth configuration을 앱의 `Info.plist` build setting으로 주입한다. 값이 비어 있으면
해당 provider는 `Not configured`으로 남아야 하며, 사용자 token은 소스·SQLite·backup에 넣지
않는다. Google Desktop secret은 Git에 포함되지 않는 루트 `.env` 또는 CI secret으로만 빌드에
주입한다. 설치형 앱에서는 추출 가능하므로 서버 비밀로 취급하지 않으며 최종 사용자는 별도
secret을 입력하지 않는다.

| Provider | Client configuration | Redirect key | 등록 방식 |
| --- | --- | --- | --- |
| Google Tasks | `BriefCalGoogleTasksClientID`; `BriefCalGoogleTasksClientSecret` ← `.env`/CI | `BriefCalGoogleTasksRedirectURI` = `http://127.0.0.1` | Google Cloud의 Desktop OAuth client + dynamic loopback port |
| Todoist | `BriefCalTodoistClientID` | `BriefCalTodoistRedirectURI` | PKCE public client; `Client ID Metadata Document` URL과 HTTPS redirect를 Todoist에 등록 |

Todoist의 production redirect는 HTTPS metadata callback이므로, standalone app의 HTTP
loopback handler와 동일시하지 않는다. 배포용 HTTPS callback/return-to-app 흐름이 제공되기
전에는 Settings가 이를 성공한 연결로 표시하지 않는다.

## T2-Google

> Cloud 준비: Tasks API, External/Testing audience, test user, Desktop OAuth client와 공개
> Debug/Release client ID 주입 완료. 실제 계정 live gate와 residue 0 판정은 대기 중이다.

### 범위

- Google account 연결과 task list 선택
- 제목, notes, date-only due, status의 양방향 sync
- account/list/cursor 저장과 remote deletion missing 처리
- 캘린더별 destination과 `Google Tasks · <list>` badge

Google Tasks의 `due`는 RFC 3339 모양이지만 시간 부분을 보존하지 않는다. 전용 civil-date
codec이 사용자의 연·월·일을 `YYYY-MM-DDT00:00:00.000Z`로 보내고 UTC/KST/DST 지역에서 같은
연·월·일의 local midnight로 복원한다. PATCH의 due 변경 없음은 필드를 생략하고 기한 제거는
명시적 JSON `null`로 보낸다. 실제 API가 `null`을 거부하면 다른 write로 우회하지 않고
T2-Google live gate 실패로 기록한다.

Google Calendar 직접 API는 T2에서 구현하지 않는다. macOS EventKit이 이미 제공하는
Google Calendar event를 다시 수집해 duplicate event를 만들지 않기 위해 T4로 분리한다.

### 검증

- PKCE success/cancel/denied/expired token
- task list 변경, remote completion, remote deletion, cursor reset
- due의 UTC/KST/America/New_York civil-date round-trip과 명시적 기한 제거
- 동일 account의 두 list에서 같은 remote ID가 섞이지 않는지
- 실제 테스트 account에서 Before/During/After 생성→완료→삭제→cleanup

## T2-Todoist

### 범위

- Todoist API v1 기준 OAuth 연결
- Inbox/project/section 선택
- title, description, due, completed, priority, project/section 표시·동기화와 같은 account 이동
- webhook을 사용할 수 있는 환경에서는 webhook, 그렇지 않으면 bounded refresh
- 상세 project/label/filter 관리가 아닌 linked task와 source 표시

webhook을 받는 서버가 없는 배포 형태에서는 주기적 refresh만 제공한다. webhook을
지원한다고 문서에 쓰려면 endpoint 인증·재시도·중복 event 처리까지 별도 검증한다.

### 검증

- API v1 endpoint와 scope를 고정하고 deprecated API를 사용하지 않음
- project/Inbox 변경, 완료·삭제·재연결
- webhook duplicate/out-of-order 또는 polling 중복 제거
- due/timezone mapping capability와 local-only fallback
- 실제 테스트 project에서 task residue 0 cleanup

## 충돌·재연결 규칙

- provider version/etag가 있으면 expected version과 함께 update한다.
- 충돌 시 local draft와 remote value를 함께 보여 주고 선택 전 write하지 않는다.
- remote deletion은 local task를 조용히 삭제하지 않고 missing으로 남긴다.
- account 재연결 뒤 같은 account/list/remote ID가 확인될 때만 relink 후보를 만든다.
- destination 변경은 기본적으로 새 task부터 적용한다. 기존 remote task는 local-only로
  전환하거나 유지하는 선택을 명시하며 자동 이동·복제하지 않는다.

## 남은 종료 게이트

Google과 Todoist 각각에 대해 OAuth·list 선택·생성·외부 완료·삭제·재연결·권한 철회와
실제 cleanup을 완료해야 한다. 한 provider만 통과하면 `T2 partial`이며 다음 provider의
실패를 숨기지 않는다. 두 provider 모두 token/본문 backup audit와 local-only regression을
통과한 뒤에만 T3를 시작한다.

Google Auth Platform이 External/Testing인 동안 Tasks scope를 승인한 refresh token은 7일 뒤
만료될 수 있다. 개발 gate에서는 재연결을 정상 복구 시나리오로 포함하고, 공개 사용자용 OAuth
verification과 production publishing은 별도 release blocker로 유지한다.
