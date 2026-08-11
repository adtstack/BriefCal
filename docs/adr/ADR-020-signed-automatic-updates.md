# ADR-020: 서명된 direct-download 자동업데이트

> 상태: Accepted
> 날짜: 2026-07-25
> 관계: ADR-006, ADR-019, Distribution, Release Runbook

## 결정

Mac App Store 밖에서 전달하는 BriefCal 빌드는 Sparkle 2를 사용해 자동업데이트할 수 있다.
업데이터는 다음 조건을 모두 만족하는 빌드에서만 시작한다.

1. `SUFeedURL`이 host를 가진 HTTPS URL이다.
2. `SUPublicEDKey`가 32-byte Ed25519 공개 키의 올바른 base64 표현이다.
3. appcast와 update archive가 같은 Sparkle private key로 서명된다.
4. update archive 안의 앱이 BriefCal의 승인된 Developer ID identity로 서명되고 notarization
   및 stapling gate를 통과한다.
5. 새 build의 `CFBundleVersion`은 설치된 build보다 큰 고유 정수다.

위 구성이 없거나 잘못된 개발·ad-hoc 빌드는 정상 실행하되 updater를 시작하지 않는다.
Sparkle을 포함한 ad-hoc app과 framework에는 Developer ID Team identity가 없으므로 hardened
runtime의 library validation을 배포 서명 대신 흉내 내는 용도로 사용하지 않는다. 명시적인
`BriefCalLocalTestBuild=YES` 산출물만 hardened runtime을 비활성화하고 in-memory fixture launch
smoke를 통과한다. 실제 배포 산출물은 marker가 `NO`이고 앱과 모든 nested code를 같은 승인된
Developer ID Team으로 서명한 뒤 hardened runtime을 유지한다.
현재 GitHub Actions가 만드는 `*-local.dmg` prerelease는 Developer ID/notarization 증거가
아니므로 자동업데이트 feed에 넣지 않는다.

구성된 빌드는 Sparkle의 정기 확인과 자동 설치를 활성화하고, 앱 메뉴에서 사용자가 직접
`Check for Updates…`를 실행할 수도 있다. feed 장애, offline 또는 서명 검증 실패는 일정,
Event Brief, local task와 backup 기능을 막거나 사용자 데이터를 변경해서는 안 된다.

## 보안·개인정보 경계

- Sparkle private key는 저장소, `.env`, 앱 번들, CI log와 release note에 넣지 않는다.
  로컬 release에서는 macOS Keychain을 사용하고, CI를 도입하면 별도 secret과 최소 권한
  runner에서만 일시적으로 제공한다.
- 앱에는 feed URL과 공개 키만 포함한다. `SURequireSignedFeed`와
  `SUVerifyUpdateBeforeExtraction`을 활성화한다.
- Sparkle anonymous system profiling은 Info.plist와 updater runtime에서 모두 비활성화한다.
- updater 요청에는 Calendar/Event Brief/task/backup 본문, provider credential, OAuth token,
  account/calendar/event identifier를 추가하지 않는다. 정적 HTTPS host에는 통상적인 연결
  metadata와 요청 IP가 보일 수 있다.
- feed나 archive가 공격받거나 잘못 배포되더라도 Ed25519와 Developer ID 검증을 우회하는
  fallback을 제공하지 않는다.
- App Sandbox 설치 helper를 위해 Sparkle이 요구하는 launcher service와 BriefCal bundle
  identifier로 한정된 `-spks`, `-spki` mach lookup 예외만 허용한다.

## 운영 계약

1. 첫 updater 포함 build를 배포하기 전에 Sparkle key를 한 번 생성하고 복구 가능한 보안
   위치에 별도 backup한다. 키를 잃으면 기존 설치본에 같은 신뢰 체인의 update를 제공할 수
   없다.
2. feed URL과 공개 키는 release build setting으로 주입한다. 공개 키를 바꾸는 migration은
   기존 키로 서명된 bridge release와 별도 ADR 없이는 진행하지 않는다.
3. notarized ZIP 또는 DMG와 release notes를 고정된 HTTPS 경로에 올린 뒤 Sparkle
   `generate_appcast`로 archive와 appcast를 서명한다. 서명 뒤 파일을 수정하지 않는다.
4. 공개 전 직전 지원 build에서 새 build 발견, download, 검증, 설치, 재실행, version/build,
   local DB 보존을 실제 사용자 계정에서 확인한다.
5. 철회가 필요하면 손상 artifact와 feed entry를 보존해 조사하고 더 높은 build number의
   forward fix를 발행한다. 호환성이 증명되지 않은 binary downgrade를 자동화하지 않는다.
6. local-test app은 signature integrity 검사만으로 통과시키지 않고 Sparkle을 실제 load한 채
   일정 시간 생존하는 launch smoke를 app과 packaged DMG 양쪽에서 실행한다.

## 결과

- automatic update는 ADR-019가 허용한 최소 배포 서비스이며 BriefCal Cloud, 계정, telemetry,
  remote config 또는 사용자 데이터 sync가 아니다.
- TestFlight와 Mac App Store 빌드에는 이 direct-download updater를 함께 사용하지 않는다.
- 앱 코드가 준비됐다는 사실은 feed, Developer ID, notarization과 end-to-end upgrade gate가
  완료됐다는 뜻이 아니다. 해당 외부 입력이 준비될 때까지 updater는 의도적으로 dormant다.

## 인수 기준

1. 올바른 HTTPS feed와 32-byte base64 공개 키만 구성이 유효하다고 판정한다.
2. 구성 없는 빌드는 Sparkle updater를 시작하지 않고 `Check for Updates…`를 비활성화한다.
3. 구성된 앱 번들에는 Sparkle framework와 installer/downloader helper가 포함되고 Sandbox
   entitlement가 exact bundle-scoped mach service만 허용한다.
4. 전체 자동 회귀, strict code-sign audit와 실제 이전-build upgrade smoke를 서로 다른
   증거로 기록한다.
5. private key 또는 사용자 데이터가 source, app bundle, appcast, artifact와 log에 없어야
   하고 Sparkle system profile 전송이 비활성 상태여야 한다.
6. local-test artifact는 marker `YES`·hardened runtime 비활성·실제 launch 성공을, Developer ID
   artifact는 marker `NO`·hardened runtime·동일 Team 서명·notarization을 각각 검증한다.
