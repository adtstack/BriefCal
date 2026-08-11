# ADR-021: BriefCal 미출시 제품 식별자 기준선

> 상태: Accepted
> 날짜: 2026-08-07
> 관계: ADR-005, ADR-006, ADR-013, ADR-015, ADR-019, ADR-020

## 배경

제품은 아직 공개·비공개 배포되지 않았고 유지해야 할 설치 사용자, 운영 데이터, backup,
Keychain credential 또는 update chain이 없다. 따라서 개발 중 사용한 임시 식별자를 호환
목적으로 남기지 않고 정식 제품명 `BriefCal` 하나로 통일할 수 있다.

제품명만 바꾸고 bundle identifier, 저장 경로, backup 형식, URL scheme 또는 빌드 변수를
임시 값으로 남기면 출시 뒤 영구 호환 부담이 된다. 첫 배포 전에 모든 공개·내부 식별자를
같은 기준으로 정리한다.

## 결정

- 제품명, 앱 표시명, Xcode project·scheme·target·module, executable과 배포 artifact는
  `BriefCal`을 사용한다.
- main bundle identifier는 `com.adtstack.briefcal`이다. test target은 각각
  `com.adtstack.briefcal.tests`, `com.adtstack.briefcal.uitests`를 사용한다.
- Application Support directory와 active DB는 `BriefCal/briefcal.sqlite`다.
- backup manifest application identifier와 SQLite entry는
  `com.adtstack.briefcal`, `briefcal.sqlite`다.
- Keychain fallback service, EventKit store label, Sparkle helper scope와 내부 payload prefix는
  `briefcal` namespace를 사용한다.
- build·CI·QA environment key와 compilation condition은 `BRIEFCAL_*`를 사용한다.
- task deep link는 `briefcal://task/<id>` 하나만 등록·생성·처리한다.
- 미출시 임시 DB, backup과 binary artifact에는 migration 또는 호환 reader를 제공하지 않는다.
  필요하면 삭제하고 새 BriefCal build에서 다시 만든다.
- 현재 작업 트리의 소스, 설정, 문서와 배포 산출물에는 폐기한 임시 제품 식별자를 남기지
  않는다.

## 결과

- 첫 배포부터 macOS 권한, sandbox container, local data, Keychain, backup과 update chain의
  영구 기준이 BriefCal로 시작한다.
- 이전 개발 build의 로컬 DB, credential, backup과 deep link는 호환 대상이 아니다.
- 향후 이 식별자를 바꾸려면 실제 사용자 migration, rollback과 update bridge를 정의한 새
  ADR이 필요하다.

## 인수 기준

1. `BriefCal.xcodeproj`의 shared `BriefCal` scheme으로 app과 test target을 빌드할 수 있다.
2. app 표시명과 executable은 `BriefCal`, bundle identifier는 `com.adtstack.briefcal`이다.
3. 기본 DB URL, backup manifest·entry, Keychain·EventKit·Sparkle 식별자가 BriefCal namespace를
   사용한다.
4. `briefcal://task/<id>`만 등록하고 strong local lookup 경계로 처리한다.
5. 현재 작업 트리의 대소문자 비구분 잔여 식별자 검사, 전체 unit suite와 Local Test Release
   launch smoke를 통과한다.
