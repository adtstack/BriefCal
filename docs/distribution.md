# Distribution

> 현재 구현·배포 준비 판정은 [Current Status](current-status.md), 실제 배포 명령과
> 중단 조건은 [Release Runbook](release-runbook.md)을 따른다.

## 배포 방향

KaosCal v1은 direct download first로 간다.
Mac App Store는 sandbox, 심사, 라이선스 정책, 업데이트 전략이 안정된 뒤 검토한다.

첫 베타의 최소 지원 버전은 macOS 14이며, Exchange 지원 문구는 macOS Calendar에 구성된 Exchange Online calendar로 한정한다.

이유:
- 구독 없는 one-time license 모델과 직접 배포가 잘 맞는다.
- local-first 제품이라 서버 비용을 낮출 수 있다.
- 베타 사용자에게 빠르게 빌드를 전달하고 피드백을 받을 수 있다.

## 출시 단계

| 단계 | 목적 | 배포 방식 |
| --- | --- | --- |
| Internal alpha | 핵심 데모 검증 | 개발자 Mac 직접 실행 |
| Private beta | 3-5명 사용성 검증 | notarized dmg 또는 zip |
| Paid beta | 구매 의향 검증 | direct download + license placeholder |
| v1 launch | 공개 출시 | direct download + license provider |

## Direct distribution 요구사항

- Developer ID Application signing
- notarization
- stapling
- dmg 또는 zip packaging
- crash-safe update 안내
- privacy 문구
- license key 또는 결제 provider 결정
- 앱 배포 라이선스/EULA 결정
- third-party notice 포함
- 공개 support·security 연락 경로 확정

## Notarization 전 체크리스트

- bundle identifier 확정
- app icon 포함
- version/build number 설정
- hardened runtime 설정
- entitlements 검토
- Calendar usage description 문구 검토
- release build에서 debug menu 제거
- clean machine에서 실행 테스트

## License 전략

v1 기본 모델:
- 무료 체험
- one-time license
- 구독 없음
- 선택적 유료 업데이트

초기에는 license placeholder로 시작할 수 있다.
결제 provider는 Paddle, Lemon Squeezy, Gumroad 같은 선택지를 출시 전 비교한다.
현재 저장소의 [Beta License Placeholder](../BETA-LICENSE.md)는 배포 허가가 아니라 미정
publisher/contact/terms 목록과 중단선이다. 승인된 실제 EULA로 대체되기 전에는 공개 또는
유료 beta artifact를 배포하지 않는다.

## 가격 초안

| 단계 | 가격 | 설명 |
| --- | --- | --- |
| Early beta | 무료 또는 초대제 | 피드백 확보 |
| Launch | $29 one-time | 14일 또는 30일 무료 체험 |
| Stable v1 | $39 one-time | 개인 사용자 직접 판매 |
| Mature v2 | $49 one-time + optional paid upgrades | 장기 유지비 반영 |

## 개인정보 문구 초안

아래 문구는 landing page용 요약 초안이다. 실제 데이터 범위, plaintext backup과 보관
책임은 저장소 루트의 [Privacy](../PRIVACY.md)를 우선하며, 외부 배포 전 publisher와
문의 경로를 확정해야 한다.

```text
KaosCal은 계정 가입 없이 작동합니다.
일정 자체는 사용자의 기존 캘린더 계정에 저장됩니다.
KaosCal의 체크리스트, 메모, 후속 작업, 변경 기록은 이 Mac의 로컬 데이터베이스에 저장됩니다.
KaosCal v1은 서버로 Event Brief 데이터를 전송하지 않습니다.
```

## 베타 릴리즈 체크리스트

- 핵심 데모 end-to-end 성공
- 권한 거부/허용 플로우 확인
- read-only 캘린더 확인
- Event Brief 재실행 후 유지
- 원본 notes 오염 없음
- 일정 이동 후 change log 기록
- backup export/import 성공
- 새 Mac 사용자 계정에서 실행 성공
- release notes 작성
- feedback 이메일 또는 form 준비
- 사용자 가이드와 known issues 공개
- Privacy·Security·앱 라이선스/EULA·third-party notice 검토
- release artifact checksum과 철회/rollback 절차 기록

## Landing page 최소 구성

- 제품명: KaosCal
- 태그라인: Tame calendar chaos.
- 설명: 일정만 보지 말고, 그 일정에 딸린 일까지 관리하세요.
- 신뢰 문구: No subscription. No account required. Your event context stays on your Mac.
- 다운로드 버튼
- 개인정보/로컬 저장 정책
- 가격 또는 베타 신청
