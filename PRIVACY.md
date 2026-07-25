# KaosCal 개인정보 및 데이터 처리 안내

> 마지막 갱신: 2026-07-20
>
> 이 문서는 현재 저장소 구현이 실제로 처리하는 데이터를 설명하는 기술적
> 안내다. 외부 배포 주체의 법적 명칭·주소, 개인정보 문의 연락처, 관할별 법적 근거와
> 최종 보존 정책은 아직 결정되지 않았다. 따라서 이 문서를 확정된 상용 서비스의 법률
> 고지로 해석해서는 안 되며, 외부 베타 전에 미정 항목을 확정해야 한다.

## 요약

KaosCal은 계정 가입 없이 작동하는 macOS 앱이다. 원본 일정은 macOS EventKit을 통해
사용자가 이미 구성한 Calendar 계정에 저장된다. KaosCal의 Event Brief, 작업, 로컬
notes, 연결 정보, calendar role·usage, saved Calendar Set과 변경 기록은 이 Mac의 로컬
SQLite에 저장된다.

현재 앱 코드에는 KaosCal 서버, 자체 계정 시스템, AI SDK/API, 분석/광고 SDK 또는
crash-reporting SDK가 없다. Calendar는 macOS EventKit만 사용한다. 사용자가 Event Brief
task destination을 명시적으로 연결하면 이 Mac의 client가 Apple Reminders, Google Tasks,
Todoist 또는 Microsoft To Do provider와 직접 통신할 수 있지만 KaosCal 중계 서버는
사용하지 않는다. 사용자가 backup을 cloud-mounted 폴더에 저장하면 해당 파일은 macOS와
그 위치의 제공자에 의해 전송될 수 있으며, 이는 KaosCal Cloud 기능이 아니다.

## KaosCal이 접근하는 데이터

### macOS Calendar 데이터

사용자가 `Full Calendar Access`를 허용하면 KaosCal은 EventKit에서 다음과 같은 정보를
읽어 화면 표시, 편집 안전성 확인, 연결 복구와 중복 후보 계산에 사용한다.

- 캘린더 이름·identifier·색상·수정 가능 여부와 source 이름·계정 유형
- 일정 제목, 위치, 시작/종료, 종일 여부, 시간대와 floating 의미
- 반복 규칙, occurrence/detached 상태와 EventKit identifier
- 원본 일정 notes
- 초대인지 판단하기 위한 organizer의 current-user 여부, 참석자 존재 여부,
  cancellation 상태

KaosCal은 사용자 요청 없이 RSVP하거나 참석자 목록을 변경하지 않는다. 지원되는 새
일정 생성, 원본 편집 또는 원본 삭제를 사용자가 명시적으로 확인하면 해당 변경은
EventKit을 거쳐 연결된 Calendar 계정에 반영될 수 있다. 캘린더 제공자가 서버에
저장·전송하는 데이터에는 해당 제공자의 개인정보 정책이 적용된다.

권한은 macOS System Settings에서 거부하거나 취소할 수 있다. 권한 취소는 KaosCal의
기존 로컬 DB나 사용자가 만든 backup을 자동 삭제하지 않는다.

### Task provider 데이터

사용자가 Settings에서 provider account와 destination을 명시적으로 연결하면 KaosCal은
provider API 또는 Apple Reminders EventKit 경계를 통해 다음 최소 데이터를 읽거나 쓸 수 있다.

- account/list/project의 stable identifier와 표시 이름
- 연결한 event task와 오른쪽 `Tasks`에서 사용자가 관리하는 일반 provider task의 제목,
  notes, due, 완료·priority 상태와 provider가 제공하는 version
- binding, pending operation, conflict/missing 상태와 opaque sync cursor

OAuth access/refresh token은 macOS Keychain에 저장하며 SQLite, ZIP과 log에 넣지 않는다.
Google Tasks, Todoist와 Microsoft To Do 통신은 이 Mac에서 해당 provider endpoint로 직접
이루어진다. 각 provider가 처리하는 원격 task 데이터에는 해당 provider의 정책이 적용된다.
일반 provider task의 notes는 상세 조회·편집 중 메모리에서만 사용하고 KaosCal SQLite나
backup에 복제하지 않는다. Provider를 연결하지 않으면 이 직접 통신은 필요하지 않고
local-only 기능은 계속 동작한다.

### KaosCal 로컬 데이터

다음 정보가 `kaoscal.sqlite`에 저장될 수 있다.

- Event Brief의 Before/During/After task와 로컬 notes
- 일정과 연결되지 않은 Personal task
- local Event/Personal task의 priority·중요 표시·반복·예상/실제 시간·timer·checklist
- 연결 일정의 제목, 시간, 위치, calendar/source 이름과 identifier, recurrence 및
  occurrence 식별 snapshot
- Event Brief lifecycle과 missing/orphan/relink 상태
- 원본 일정 변경 기록과 versioned before/after snapshot; 이 snapshot에는 원본 event
  notes가 포함될 수 있음
- 사용자가 명시한 local calendar role preference
- calendar별 표시·availability-blocking preference
- saved Calendar Set 이름·순서, exact calendar membership과 현재 선택
- provider account/list/item 최소 cache, binding, pending operation, sync cursor와 task별
  local-only preference

단순히 일정을 읽는 것만으로 Event Brief row를 만들지는 않는다. 사용자가 notes/task를
저장하거나 연결이 필요한 동작을 수행할 때 관련 로컬 row가 만들어질 수 있고, 강한
EventKit 식별자로 연결된 row의 일정 snapshot은 이후 refresh에서 갱신될 수 있다.

KaosCal은 Exchange/task-provider password, MFA code, tenant/client secret을 앱 입력으로
요청하거나 SQLite에 저장하지 않는다. provider OAuth token은 연결 과정에서 받아 Keychain에만
저장한다. 참석자 전체 목록과 EventKit 전체 event store도 전용 로컬 사본으로 저장하지
않는다. 그러나 사용자가 Event Brief notes, task, Personal task 또는 원본 event notes 본문에
비밀번호·token·개인정보를 직접 입력하면 그 텍스트는 검사하거나 가리지 않으므로 로컬 DB,
변경 snapshot 또는 backup에 포함될 수 있다.

## 저장 위치와 보안 경계

production 앱의 active DB는 App Sandbox의 user Application Support 아래
`KaosCal/kaoscal.sqlite`에 저장된다. 실제 경로는 앱의 **Settings > Local Data >
Storage**에서 확인할 수 있다. 일반적인 현재 bundle identifier의 경로는 다음과 같다.

```text
~/Library/Containers/com.adtstack.kaoscal/Data/Library/Application Support/KaosCal/
```

KaosCal은 App Sandbox와 macOS Calendar 권한을 사용하지만, active SQLite에 별도의
애플리케이션 수준 암호화를 추가하지 않는다. 기기 접근 통제, FileVault, 사용자 계정과
시스템 backup의 보호 상태도 로컬 데이터의 실질적 보안에 영향을 준다.

## Backup에 포함되는 데이터

수동 export와 import/reset 전 recovery backup은 다음 두 항목만 가진 ZIP이다.

```text
manifest.json
kaoscal.sqlite
```

이 SQLite snapshot에는 Event Brief와 task, Personal task와 local planning/checklist, calendar role·usage,
saved Calendar Set 이름·membership·selection, link metadata, 변경 기록과 원본 notes
snapshot이 포함될 수 있다. 완전한 Calendar event
store, 완전한 참석자 목록, 계정 credential은 backup 전용 필드로 추가되지 않지만,
사용자 입력 본문에 들어간 민감정보는 그대로 포함될 수 있다.

- ZIP과 SQLite는 KaosCal이 암호화하거나 제작자 서명하지 않는 plaintext다.
- manifest의 SHA-256은 archive 내부 SQLite byte의 무결성을 확인할 뿐 backup 제작자나
  출처를 인증하지 않는다.
- 사용자가 고른 로컬·외장·network-mounted·cloud 위치에 수동 ZIP을 저장할 수 있다.
  해당 위치의 운영자·cloud 제공자·공유 상대가 파일에 접근할 가능성은 그 위치의 설정과
  정책에 따른다.
- Import/reset 전 자동 recovery ZIP은 active DB 옆 `KaosCal/Backups`에 저장된다.
- 현재 버전은 수동/자동 backup을 자동 만료·prune하지 않는다.

신뢰하는 위치에만 backup을 저장하고, 공유하기 전에 민감한 내용이 없는 별도 테스트
데이터로 만든 backup인지 확인한다. 실제 사용자 DB나 backup을 일반 버그 보고서에
첨부하지 않는다.

## 데이터 전송과 제3자 경계

KaosCal은 AI, telemetry, 광고, 분석, KaosCal 계정 또는 KaosCal Cloud endpoint로 사용자
데이터를 전송하지 않는다. 다음 처리는 사용자의 설정과 명시적 동작에 따라 KaosCal 외부에서
일어날 수 있다.

- macOS와 사용자가 구성한 Calendar 제공자의 일정 동기화
- 사용자가 연결한 Google Tasks, Todoist, Microsoft To Do와 이 Mac client 사이의 task
  조회·생성·수정·완료·삭제·동기화. Apple Reminders는 macOS EventKit 경계를 사용한다.
- 사용자가 클릭해 여는 conference/reference HTTPS URL
- 사용자가 선택한 iCloud Drive, OneDrive, Dropbox 또는 다른 cloud 폴더의 backup
  파일 동기화
- 서명된 direct-download build가 구성된 경우, 새 버전을 확인하고 받기 위한 Sparkle의
  정적 HTTPS appcast·archive 요청. KaosCal은 이 요청에 Calendar/Event Brief/task/backup
  본문, provider credential, OAuth token 또는 원격 식별자를 추가하지 않는다. hosting
  사업자는 통상적인 IP 주소, 요청 시각, user agent 같은 연결 metadata를 처리할 수 있다.
  Sparkle의 선택적 anonymous system profile 전송은 plist와 runtime에서 모두 끈다.
- macOS 자체의 시스템 backup, 진단 또는 보안 기능

KaosCal은 이 외부 서비스의 계정, 보존, 공유 또는 삭제 정책을 제어하지 않는다.
GRDB는 앱 내부의 로컬 SQLite 접근에 사용되고, Sparkle은 구성된 direct-download build의
업데이트 확인·검증·설치에만 사용된다. feed 구성이 없는 개발 빌드는 updater를 시작하지
않는다.

## 보존과 삭제

- Active local data는 사용자가 삭제하거나 `Reset Local Data`를 실행할 때까지 남을 수
  있다. 완료된 task, 변경 history와 unavailable saved Set membership도 기능상 보존될 수 있다.
- 원본 일정이 없어져도 Event Brief를 즉시 자동 삭제하지 않는다. 사용자는 orphan으로
  보관, 다른 일정에 relink 또는 `Delete Local Brief`를 선택할 수 있다.
- `Delete Local Brief`와 `Reset Local Data`는 Calendar/Exchange 원본을 삭제하지 않는다.
- `Reset Local Data`는 실행 전 recovery backup을 만들므로 active row를 지운 뒤에도
  plaintext ZIP에 데이터가 남는다. 이 ZIP은 사용자가 별도로 삭제해야 한다.
- 앱 번들을 제거하는 것만으로 Application Support 데이터, 자동 recovery backup 또는
  사용자가 export한 ZIP이 모두 삭제된다고 보장하지 않는다.
- Calendar 계정에 저장된 원본 일정의 보존·삭제는 Calendar.app과 해당 제공자에서
  별도로 관리한다.

KaosCal은 서버 계정이나 서버 측 Event Brief 저장소를 운영하지 않으므로 현재
구현에는 원격 데이터 열람·삭제 요청을 처리할 서버 데이터가 없다. 로컬 데이터 제거
방법은 [사용자 가이드](docs/user-guide.md#8-데이터-위치와-앱-제거)를 따른다.

## 미정인 법적·운영 정보

다음 항목은 현재 저장소에서 확정되지 않았으며 추정해 기재하지 않는다.

- 외부 배포/개인정보 처리 주체의 법적 명칭과 주소
- 모니터링되는 개인정보 문의 이메일 또는 form
- 판매 지역별 법적 근거, 사용자 권리 접수 절차와 응답 기한
- 연령 제한, 아동 대상 여부, 국제 이전 및 지역별 추가 고지
- 실제 update HTTPS hosting 사업자와 log 보존 기간
- 배포 후 local-only 진단, 결제 또는 라이선스 제공자를 도입할지 여부와 그 최소 데이터 경계

AI, KaosCal 서버·계정·Cloud, telemetry와 remote analytics는
[ADR-019](docs/adr/ADR-019-local-only-no-ai-no-kaoscal-cloud.md)에 따라 제품 범위에서 영구
제외한다. 자동업데이트의 최소 경계는
[ADR-020](docs/adr/ADR-020-signed-automatic-updates.md)에 고정했다. 실제 hosting,
결제·license 또는 local-only 진단 경계가 결정되면 배포 전에 이 문서를 실제 데이터
흐름에 맞게 갱신해야 한다. 보안 취약점 보고의 현재 경계는
[SECURITY.md](SECURITY.md)를 참고한다.
