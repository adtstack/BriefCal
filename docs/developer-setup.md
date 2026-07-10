# Developer And Test Setup

> 상태: Phase 0 완료 / Phase 1 실계정 검증 준비
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

5. **앱 권한 — 앱 실행 시 확인**
   - 사용자가 full calendar access 요청을 허용할 예정이다.

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

## 제공하지 않아도 되는 것

- 로고, 앱 아이콘, 색상 팔레트, 와이어프레임
- 실제 회사 일정 또는 고객 정보
- Exchange 자격 증명

원본 디자인은 BusyCal의 정보 밀도와 작업 흐름만 참고하고, KaosCal만의 색·아이콘·레이아웃으로 만든다.
