# Developer And Test Setup

> 현재 개발·검증 상태: [Current Status](current-status.md)를 단일 기준으로 사용
> 마지막 갱신: 2026-07-21

KaosCal의 디자인·문구·임시 아이콘·제품 정책은 프로젝트에서 결정하고 기록한다. 사용자가 우선 준비할 것은 개발·실계정 검증에 필요한 아래 항목뿐이다.

## 지금 필요한 것

1. **전체 Xcode 설치 — 완료**
   - Xcode 26.6 / Build 17F113을 확인했다.

2. **테스트 전용 Exchange 계정 또는 mailbox — 완료**
   - 같은 Mac의 System Settings > Internet Accounts에 로그인되어 있다.
   - Calendar 동기화가 활성화되어 있다.
   - Outlook connector는 mailbox time zone을 `Korea Standard Time`으로 반환했지만 MSA 제한도 보고했다. 이 결과만으로 같은 Mac의 EventKit 계정을 Exchange Online 또는 온프레미스로 판정하지 않는다.
   - 계정 비밀번호, MFA 코드, 관리 토큰은 KaosCal 저장소나 대화에 절대 공유하지 않는다.

3. **수정해도 되는 테스트 캘린더 두 개 — 사용자 지정 / 서버·EventKit 확인 완료**
   - source calendar: `KAOS-TEST`
   - destination calendar: `일정`
   - 사용자가 두 캘린더의 고유 QA fixture write를 허용했으며 추가 캘린더를 만들 필요가 없다.
   - Outlook connector run `20260711-1512-7C4E`에서는 exact-name match가 각각 하나이고 editable·distinct·same owner임을 확인했다.
   - FinalRelease EventKit run `20260711-1626-B7D2`에서는 앱 sidebar에 두 캘린더가 모두 `Exchange`이고 잠금 없는 writable 상태로 표시되는 것을 확인했다.
   - `일정`이 비어 있다고 가정하지 않는다. 두 캘린더의 기존 일정은 읽기 범위에 포함될 수 있어도 수정·삭제하지 않고, 고유 run marker가 붙은 fixture만 정확히 정리한다.
   - 가능하면 별도의 공유 read-only 캘린더 `KaosCal Exchange Viewer`도 준비한다.
   - 회사 실일정·고객 정보가 담긴 calendar는 사용하지 않는다.

4. **조직 정책 확인**
   - macOS Calendar의 Exchange 동기화와 EventKit 기반 일정 수정이 회사 MDM/보안 정책상 허용되는지 확인한다.

5. **앱 권한 — recurrence-fix live artifact 확인 완료**
   - 2026-07-11 live run에서 검증 대상 build의 `Full calendar access`와 실제 EventKit fetch를 확인했다.
   - 새 ad-hoc build가 다시 요청하면 `Allow Full Calendar Access`를 누르고 macOS 요청을 허용한다.
   - KaosCal에는 비밀번호, MFA 코드, tenant ID, OAuth token을 입력하지 않는다.

## 지금 사용자가 할 일

현재 개발 진행을 위해 사용자가 준비할 추가 비밀정보나 캘린더는 없다. 기본 비반복 EventKit create/update/delete gate는 완료됐고, 아래 항목 중 1~3도 확인됐다. 나머지는 사용자가 컴퓨터를 사용할 수 있을 때 Calendar.app 시각 확인과 별도 고유 fixture로 이어가면 된다.

1. **확인 완료:** 좌측 권한 상태가 `Full calendar access`로 보인다. 새 build가 다시 요청할 때만 한 번 허용한다.
2. **확인 완료:** `KAOS-TEST`와 `일정`이 sidebar에서 `Exchange`, 잠금 없는 수정 가능 상태로 보인다.
3. **확인 완료:** 민감하지 않은 비반복 fixture가 생성되고 앱 재실행·refetch 뒤에도 반복 badge나 scope 없이 단일 일정으로 수정·삭제된다. Outlook 서버에서도 생성·수정 뒤 `singleInstance`·recurrence 없음이며 최종 source/destination residue는 `0/0`이다.
4. **남은 시각 gate:** `KC-E1`의 생성·수정·삭제가 Calendar.app에 보이는지 확인한다.
5. **남은 기능 gate:** `KC-E2` 종일 범위와 `KC-E3` floating/zoned 변경을 확인한다.
6. **남은 Phase 6 gate:** `KC-E4`의 `이번 일정`/`이번 이후`와 future split을 확인한다.
7. **남은 이동 gate:** `KAOS-TEST`→`일정` linked calendar move를 별도 fixture로 확인한다.
8. **남은 Phase 7C gate:** 비반복 linked original delete는 run `20260712-025027-KST`에서 통과했다. 별도 반복 fixture의 `이번 일정` 삭제와 retained single local Brief의 UI-only cleanup은 series 잔존·원본 비재생성·exact cleanup을 전제로 확인한다. `이번 이후`는 누르지 않는다.

실제 회사 일정은 수정하지 않고 모든 write는 `KAOS-TEST`와 `일정`에서 고유 run marker로 만든 전용 fixture에만 수행한다.

## Google Tasks 개발 계정 설정

Google Tasks 실계정 gate는 Calendar 계정과 분리해 아래 순서로 준비한다. Google Calendar
일정은 계속 macOS EventKit으로 읽고 쓰며 Calendar API는 이 설정에서 활성화하거나 scope에
추가하지 않는다.

1. Google Cloud 프로젝트에서 **Google Tasks API**를 활성화한다.
2. Google Auth Platform의 audience를 **External**, publishing status를 **Testing**으로 두고
   검증에 사용할 Google 계정을 test user로 추가한다.
3. data access에는 `openid`, `email`, `profile`,
   `https://www.googleapis.com/auth/tasks`만 등록한다.
4. OAuth client type **Desktop app**을 만든다. client secret은 앱, 저장소, SQLite, backup,
   로그 또는 QA 기록에 복사하지 않는다.
5. 공개 client ID를 app target의 user-defined build setting
   `KAOSCAL_GOOGLE_TASKS_CLIENT_ID`에 넣는다. `Info.plist`의
   `KaosCalGoogleTasksClientID`가 이 값을 확장하며,
   `KaosCalGoogleTasksRedirectURI`는 포트 없는 `http://127.0.0.1` base다. KaosCal은 연결할
   때마다 임의 가용 포트를 확보해 authorization과 token exchange에 같은 실제 redirect URI를
   사용한다. 값이 비어 있으면 Settings는 안전하게 `Not configured`을 표시한다.

Testing 상태에서 외부 test user가 승인한 refresh token은 Tasks scope가 포함된 이 구성에서
7일 뒤 만료될 수 있다. 이는 개발 중 재연결 사유이며 데이터 삭제 사유가 아니다. 공개 배포 전
Google OAuth app verification과 production publishing 전환을 별도 release blocker로 판정한다.

실계정 검증은 민감하지 않은 전용 Google Tasks 목록과 `KAOS-GTASK-<UTC timestamp>-<random>`
형식의 고유 run marker만 사용한다. 기존 사용자 task를 수정하지 않고, 종료 시 marker로 만든
원격 task와 KaosCal의 연결 fixture를 정확히 삭제해 양쪽 residue가 0인지 확인한다. access token,
refresh token, authorization code, 계정 email은 문서나 implementation log에 기록하지 않는다.

저장소의 `ManualEventKitQATests/testManualExchangeGate`는 검증 대상 signed host의 상태를 확인하기 위한 **읽기 전용 opt-in preflight**다. `KAOSCAL_EVENTKIT_QA_MODE=inspect`, `KAOSCAL_EVENTKIT_SOURCE=KAOS-TEST`, `KAOSCAL_EVENTKIT_DESTINATION=일정`을 모두 명시한 실행만 동작하며, 기본 suite에서는 provider 생성 전에 skip한다. 이 test는 `requestFullAccess()`나 calendar write를 호출하지 않고, JSON report에도 raw calendar identifier와 source title을 남기지 않는다. 권한 승인은 사용자가 해당 host의 macOS prompt에서 별도로 수행해야 한다.

Exchange 로그인 정보는 환경변수로 만들지 않는다. password, MFA, tenant/client secret, OAuth token은 앱·저장소·대화에 제공하지 않는다. Outlook connector 인증은 외부 QA 경로가 관리하며 KaosCal runtime 의존성이 아니다. connector 응답의 raw calendar/event ID, account/email, source title은 exact cleanup에만 사용하고 저장소 문서·프로젝트 로그·commit에 복사하지 않는다. macOS Internet Accounts의 기존 로그인과 Calendar 동기화 상태가 유일한 앱 계정 준비다. Phase 3의 SQLite DB와 migration은 앱이 자동으로 준비한다.

Exchange Online인지 온프레미스인지 알 수 있는 관리자 정보가 나중에 확보되면 호환성 기록에 추가하지만, 지금 개발을 막지는 않는다. 공유 read-only Exchange 캘린더는 아직 없어 그 항목의 실계정 판정만 `blocked`다. live EventKit run은 권한·source 표시·비반복 CRUD를 확인했지만 Calendar.app 시각 round-trip과 all-day·반복·이동 증거를 대신하지 않는다. 서버 connector 결과와 로컬 EventKit gate는 계속 분리한다.

## 나중에 필요한 것

- 외부 베타 배포 전: Apple Developer Team, Developer ID signing, notarization 권한
- 실제 사용자 테스트 전: 3~5명의 베타 참여자와 피드백 수집 경로

## Exchange 테스트 데이터

| ID | 만들 항목 | 검증 목적 |
| --- | --- | --- |
| KC-E1 | 90분짜리 수정 가능한 시간 일정 | 기본 읽기·수정·이동 |
| KC-E2 | 하루 및 이틀짜리 종일 일정 | 날짜 범위와 all-day lane |
| KC-E3 | `America/New_York` 등 DST 지역 시간 일정 | 시간대 표시와 변경 |
| KC-E4 | attendee 없는 6회 이상 기본 주간 반복 일정, 한 occurrence만 변경 | `이번 일정`/`이번 이후`, detached·series split, occurrence context |
| KC-E5 | 공유 read-only calendar 일정 | 원본 편집 차단과 로컬 Brief; calendar 준비 전까지 대기 |
| KC-E6 | 외부 주최 초대 일정 + 사용자가 주최한 attendee meeting | 두 유형 모두 원본 편집 차단과 local-only Brief 안전성 |

fixture는 민감하지 않은 제목과 내용, 고유 run marker로 `KAOS-TEST`에 만들고 calendar 이동 대상은 `일정`을 사용한다. KC-E4에는 attendee나 실제 연락처를 넣지 않고 KaosCal이 표현 가능한 기본 recurrence만 사용한다. Phase 6 구현·자동 gate와 서버 측 제한된 round-trip에 이어 비반복 EventKit write도 recurrence-fix signed Release(CDHash `63ded03a9d704976c4ba45340f2748eda9892382`)에서 부분 통과했다. 반복·all-day·move는 각각 별도 marker와 exact cleanup을 전제로 실행한다. 앱이나 환경변수에 account password를 넣는 fixture 자동화는 만들지 않는다.

역사적 source 상태·임시 path·CDHash·서명 검증은 [Exchange Compatibility](exchange-compatibility.md)의
build-evidence section과 [Implementation Log](implementation-log.md)에 유지한다. live run
`20260711-1626-B7D2`는 비반복 CRUD를, run `20260712-025027-KST`는 비반복 linked
original delete와 local Brief 보존을 확인했다. 어느 결과도 아직 Calendar.app 전체 시각
round-trip, all-day, 반복 `thisEvent`/future split, calendar move 또는 shared read-only
permission gate를 대신하지 않는다. 최신 suite와 Release artifact는
[Current Status](current-status.md)만 갱신한다.

## 제공하지 않아도 되는 것

- 로고, 앱 아이콘, 색상 팔레트, 와이어프레임
- 실제 회사 일정 또는 고객 정보
- Exchange 자격 증명

원본 디자인은 BusyCal의 정보 밀도와 작업 흐름만 참고하고, KaosCal만의 색·아이콘·레이아웃으로 만든다.
