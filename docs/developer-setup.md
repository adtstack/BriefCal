# Developer And Test Setup

> 상태: Phase 3 Local Context DB 자동 검증 완료 / Phase 4 UX와 실계정 권한·UI 검증 진행 중
> 마지막 갱신: 2026-07-10

KaosCal의 디자인·문구·임시 아이콘·제품 정책은 프로젝트에서 결정하고 기록한다. 사용자가 우선 준비할 것은 개발·실계정 검증에 필요한 아래 항목뿐이다.

## 지금 필요한 것

1. **전체 Xcode 설치 — 완료**
   - Xcode 26.6 / Build 17F113을 확인했다.

2. **테스트 전용 Exchange 계정 또는 mailbox — 완료**
   - 같은 Mac의 System Settings > Internet Accounts에 로그인되어 있다.
   - Calendar 동기화가 활성화되어 있다.
   - Exchange Online인지 온프레미스인지는 아직 확인되지 않았다.
   - 계정 비밀번호, MFA 코드, 관리 토큰은 KaosCal 저장소나 대화에 절대 공유하지 않는다.

3. **수정해도 되는 전용 테스트 캘린더 — 완료**
   - 캘린더 이름: `KAOS-TEST`
   - 사용자가 수정 가능하다고 확인했다.
   - 가능하면 별도의 공유 read-only 캘린더 `KaosCal Exchange Viewer`도 준비한다.
   - 회사 실일정·고객 정보가 담긴 calendar는 사용하지 않는다.

4. **조직 정책 확인**
   - macOS Calendar의 Exchange 동기화와 EventKit 기반 일정 수정이 회사 MDM/보안 정책상 허용되는지 확인한다.

5. **앱 권한 — 사용자 승인 필요**
   - 실행 중인 KaosCal에서 `Allow Full Calendar Access`를 누른다.
   - macOS가 표시하는 full calendar access 요청을 허용한다.
   - KaosCal에는 비밀번호, MFA 코드, tenant ID, OAuth token을 입력하지 않는다.

## 지금 사용자가 할 일

현재 개발 진행을 위해 사용자가 바로 준비할 추가 비밀정보는 없다. 최신 서명 KaosCal 창에서 아직 하지 않았다면 **macOS full calendar access 요청을 한 번 허용하는 것**만 필요하다. 이후 `KAOS-TEST`가 sidebar에서 `Exchange`, 캘린더 고유 색상, 수정 가능 상태로 보이고 Day/Week/Agenda에 같은 일정이 표시되는지 확인한다.

Exchange 로그인 정보는 환경변수로 만들지 않는다. password, MFA, tenant/client secret, OAuth token은 앱·저장소·대화에 제공하지 않는다. macOS Internet Accounts의 기존 로그인과 Calendar 동기화 상태가 유일한 계정 준비다. Phase 3의 SQLite DB와 migration은 앱이 자동으로 준비한다.

Exchange Online인지 온프레미스인지 알 수 있는 관리자 정보가 나중에 확보되면 호환성 기록에 추가하지만, 지금 개발을 막지는 않는다. 공유 read-only Exchange 캘린더는 아직 없어 그 항목의 실계정 판정만 `blocked`다. Phase 4 개발은 계속하되, Phase 8 호환성 게이트를 닫기 전에는 준비해야 한다.

## 나중에 필요한 것

- 외부 베타 배포 전: Apple Developer Team, Developer ID signing, notarization 권한
- 실제 사용자 테스트 전: 3~5명의 베타 참여자와 피드백 수집 경로

## Exchange 테스트 데이터

| ID | 만들 항목 | 검증 목적 |
| --- | --- | --- |
| KC-E1 | 90분짜리 수정 가능한 시간 일정 | 기본 읽기·수정·이동 |
| KC-E2 | 하루 및 이틀짜리 종일 일정 | 날짜 범위와 all-day lane |
| KC-E3 | `America/New_York` 등 DST 지역 시간 일정 | 시간대 표시와 변경 |
| KC-E4 | 6회 이상 주간 반복 일정, 한 occurrence만 변경 | 반복·detached occurrence |
| KC-E5 | 공유 read-only calendar 일정 | 원본 편집 차단과 로컬 Brief; calendar 준비 전까지 대기 |
| KC-E6 | 외부 주최 초대 일정 | 표시와 local-only Brief 안전성 |

fixture는 민감하지 않은 제목과 내용으로 `KAOS-TEST`에만 만든다. Phase 1은 읽기 전용 구현이므로 기존 안전한 테스트 일정으로 조회를 먼저 확인하고, 생성·수정 fixture 자동화는 EventKit 쓰기 단계에서 추가한다.

## 제공하지 않아도 되는 것

- 로고, 앱 아이콘, 색상 팔레트, 와이어프레임
- 실제 회사 일정 또는 고객 정보
- Exchange 자격 증명

원본 디자인은 BusyCal의 정보 밀도와 작업 흐름만 참고하고, KaosCal만의 색·아이콘·레이아웃으로 만든다.
