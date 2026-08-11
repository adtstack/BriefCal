# BriefCal 보안 정책

> 마지막 갱신: 2026-07-20
>
> BriefCal은 현재 외부 베타 준비 단계다. 모니터링되는 security 이메일, 공개 bug
> bounty, 응답 SLA 또는 GitHub private vulnerability reporting의 활성화 여부가 아직
> 확정되지 않았다. 이 문서는 그 공백을 숨기지 않고 현재 테스터와 유지관리자가 지켜야
> 할 최소 안전 경계를 정의한다.

## 취약점 신고

현재 일반 사용자가 사용할 수 있다고 확인된 전용 비공개 보안 신고 채널은 없다.
따라서 다음 원칙을 따른다.

1. 악용 가능한 세부 내용, 실제 calendar/backup 데이터, credential 또는 exploit을
   공개 GitHub issue, discussion, commit, pull request, 채팅방에 게시하지 않는다.
2. 지정 테스터라면 빌드를 전달받은 기존 비공개 채널에서 배포 담당자에게 **보안 신고
   수신 방법을 먼저 요청**한다. 첫 메시지에는 비민감 요약과 영향만 적고 exploit이나
   파일을 첨부하지 않는다.
3. 신뢰할 비공개 채널을 갖고 있지 않다면 세부 공개를 중단하고, 저장소에 공식 보안
   연락처 또는 private reporting 절차가 게시될 때까지 기다린다. 공개 issue는 안전한
   대체 채널이 아니다.
4. 유지관리자는 외부 베타 전에 모니터링되는 security contact 또는 검증된 private
   vulnerability reporting을 마련하고, 수신 확인·triage·수정·공개 절차를 이 문서에
   추가해야 한다.

현재는 접수 확인 기한, 수정 기한, 포상 또는 coordinated-disclosure embargo를 약속하지
않는다. 실제 피해가 진행 중이면 소속 조직의 incident-response 절차와 Apple 또는
영향받은 Calendar/task 제공자의 공식 지원 경로도 사용한다.

## 첫 신고에 포함할 내용

비공개 수신 경로가 확인된 뒤에도 최소 정보부터 보낸다.

- BriefCal 버전과 build 번호, macOS 버전, Mac 종류
- 문제 유형과 예상 영향
- 비민감 테스트 계정/전용 fixture로 만든 최소 재현 단계
- 기대 결과와 실제 결과
- 재현 빈도, 권한 상태, 관련 기능(EventKit, Event Brief, backup/import/reset 등)
- 사용자 이름·경로·identifier·본문을 가린 최소 로그 또는 screenshot

요청받지 않은 binary, live SQLite, ZIP backup, crash dump, Calendar export 또는
동영상은 첨부하지 않는다. 파일 전달이 반드시 필요하더라도 secure intake가 확인된 뒤
합성 fixture만 사용한다.

## 신고에 절대 포함하지 않을 정보

- Exchange/iCloud/Google 계정 password, MFA code, recovery code
- OAuth/access/refresh token, tenant/client secret, session cookie, Keychain 내용
- 실제 account/email, attendee/organizer 연락처
- raw calendar/event/item/external identifier
- 실제 일정 제목·위치·시간, 원본 event notes, Event Brief notes/task
- 실제 `briefcal.sqlite`, manual export ZIP 또는 `Backups`의 recovery ZIP
- home directory 사용자 이름, 회사명, 기기 이름처럼 로그 경로에 포함된 식별정보

BriefCal은 credential을 전용 필드로 수집하지 않지만 사용자가 notes/tasks에 입력한
비밀은 로컬 DB와 backup에 그대로 들어갈 수 있다. 비밀이 포함된 파일을 보고용으로
복사하지 말고, 해당 비밀은 원래 발급자에서 폐기·회전한다.

## 현재 보안 모델

현재 production 설계는 다음 경계를 가진다.

- App Sandbox와 macOS의 Full Calendar Access 권한을 사용한다.
- Exchange/iCloud 등 캘린더 로그인은 macOS Internet Accounts가 담당하며 BriefCal은
  account password, MFA 또는 OAuth token을 요청하지 않는다.
- 원본 일정 입출력은 EventKit만 사용하며 자체 Microsoft Graph/EWS/CalDAV Calendar sync를
  만들지 않는다.
- 사용자가 연결한 Google Tasks, Todoist와 Microsoft To Do는 이 Mac의 provider client가
  공식 endpoint로 직접 통신한다. Apple Reminders는 EventKit을 사용한다. OAuth token은
  Keychain에만 저장하고 SQLite/ZIP/log 또는 BriefCal 중계 서버에 넣지 않는다.
- AI SDK/API, BriefCal account/backend/cloud database, telemetry·광고·remote analytics와
  background content upload를 사용하지 않는다.
- 이 Mac 단일 실행·저장과 허용되는 외부 동기화 경계는
  [ADR-019](docs/adr/ADR-019-local-only-no-ai-no-product-cloud.md)을 따른다.
- direct-download updater는 유효한 HTTPS feed와 Ed25519 공개 키가 있는 빌드에서만
  시작한다. signed appcast·archive를 extraction 전에 검증하고, Developer ID/notarized
  앱만 release 대상으로 허용한다. update 요청에 사용자 본문이나 provider credential을
  추가하지 않고 Sparkle anonymous system profiling을 명시적으로 끈다.
- Sparkle private key는 source, `.env`, app bundle, CI log와 release note에 넣지 않는다.
  App Sandbox helper용 mach lookup 예외는 BriefCal bundle ID의 `-spks`, `-spki`로 한정한다.
- Sandbox 밖의 manual backup 파일은 사용자가 Open/Save panel에서 명시적으로 고른
  위치만 읽거나 쓴다.
- Event Brief/task/planning/checklist/role·usage/saved Calendar Set/change history는 로컬 SQLite에 저장된다. 앱은 live SQLite에
  별도의 애플리케이션 수준 암호화를 추가하지 않는다.
- Import는 엄격한 ZIP 구조, application identifier, 현재 schema/migration, byte
  count/SHA-256, SQLite integrity와 foreign key를 확인한다. 이 검증은 우발적 손상과
  예상하지 않은 형식을 거부하기 위한 것이며 backup 제작자를 인증하지 않는다.
- Import/reset 전에 recovery ZIP을 만들고 실패 시 rollback을 시도한다. rollback까지
  실패하면 해당 session의 local/calendar mutation과 refresh를 잠근다.

Sandbox, hash, schema 검증은 악성 software, 탈취된 사용자 계정, 물리적 접근 또는
신뢰하지 않는 backup의 안전을 보장하지 않는다.

## Backup 및 credential 경계

Manual export와 자동 recovery backup은 `manifest.json`과 `briefcal.sqlite`를 포함한
plaintext ZIP이다. 암호화나 제작자 서명이 없고, 다음 민감정보가 포함될 수 있다.

- Event Brief notes와 Before/During/After task, Personal task와 local planning/checklist
- 일정 제목·시간·위치와 calendar/source/EventKit identifier
- change snapshot과 원본 event notes snapshot
- calendar role·usage preference, saved Calendar Set 이름·membership·selection과 local lifecycle/link history

따라서 다음을 지킨다.

- 자신이 만든 신뢰 가능한 BriefCal backup만 import한다.
- ZIP의 SHA-256 일치를 출처 인증이나 malware 검사의 대체로 해석하지 않는다.
- backup을 이메일, public issue, 일반 메신저 또는 공개 cloud link로 전달하지 않는다.
- cloud 폴더를 선택하면 해당 cloud 계정의 공유, 보존, version history와 침해 위험을
  함께 고려한다.
- 자동 recovery backup은 BriefCal이 prune하지 않으므로 필요가 끝난 파일은 사용자가
  안전하게 삭제한다.
- password/token을 notes나 task에 저장하지 않는다. 이미 저장했다면 해당 비밀을
  회전하고 active DB와 모든 backup 사본을 함께 처리한다.

## 안전한 테스트 규칙

- 실제 회사/개인 일정이 아닌 별도 테스트 캘린더와 고유한 비민감 fixture를 사용한다.
- 기존 일정은 수정·삭제하지 않고, 자신이 만든 exact fixture만 정리한다.
- 실제 attendee나 연락처를 추가하지 않는다.
- 조직 정책을 우회하거나 다른 사용자의 계정·캘린더·기기에 접근하지 않는다.
- destructive import/reset, recurrence, calendar move와 delete 테스트 전에는 현재 로컬
  데이터를 보존하고 영향 범위를 확인한다.
- 서비스 거부, 대량 일정 생성, 자동 반복 mutation 또는 provider 부하 테스트는 사전
  허가 없이 수행하지 않는다.

## 사용자가 이상 징후를 발견한 경우

1. 진행 중인 import/reset/edit 작업을 반복 실행하지 말고 BriefCal을 종료한다.
2. macOS System Settings의 Calendars 권한에서 BriefCal 접근을 취소할 수 있다.
3. Application Support의 `BriefCal` 폴더와 `Backups`를 삭제하지 않은 채 별도로
   보존한다. 다만 이 파일을 공개 채널에 업로드하지 않는다.
4. 계정 credential이 BriefCal notes/task 또는 backup에 들어갔다면 원래 제공자에서
   credential을 회전하고 모든 backup 위치를 점검한다.
5. 빌드를 전달받은 비공개 채널에서 secure intake 방법을 먼저 확인한다.

## 지원 버전과 배포 신뢰 경계

현재 프로젝트 version은 개발 단계의 `0.1.2`이며 공개 보안 지원 기간이나 과거 build
지원 정책이 없다. 보고할 때는 가능하면 배포 담당자가 지정한 최신 테스터 build에서
합성 fixture로 재현 여부를 확인한다.

Developer ID 서명, notarization, stapling과 최종 DMG/ZIP 배포 절차는 아직 출시
요구사항으로 남아 있다. 저장소의 `BriefCalLocalTestBuild=YES` ad-hoc Release는 Developer ID
Team identity가 없어 hardened runtime을 비활성화하고 launch smoke를 통과하는 개발 검증
산출물일 뿐 공용 배포 provenance가 아니다. 실제 배포 build는 marker `NO`, 같은 Team의 nested
code, hardened runtime과 notarization이 필수다. 출처를 확인할 수 없는 build를 실행하거나
Gatekeeper를 우회하지 않는다.

Sparkle 2.9.2 수신기와 signed-feed 강제 정책은 구현됐지만 실제 HTTPS feed, Developer ID
update artifact와 이전-build end-to-end 설치 증거는 아직 없다. 현재 GitHub Actions의
ad-hoc `*-local.dmg`를 update feed로 사용하거나 서명 오류를 우회하지 않는다. 자세한
발행·키 회전 경계는 [ADR-020](docs/adr/ADR-020-signed-automatic-updates.md)을 따른다.

현재 알려진 제품/복구 제한은 [사용자 가이드](docs/user-guide.md#9-현재-제한과-지원-경계),
데이터 처리와 plaintext 경계는 [PRIVACY.md](PRIVACY.md), backup format은
[backup-restore.md](docs/backup-restore.md)를 참고한다.
