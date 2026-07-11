# ADR-013: 앱 아이콘과 초기 브랜드 방향

> 상태: Accepted
> 날짜: 2026-07-11

## 배경

KaosCal에는 사용자 제공 로고나 브랜드 자산이 없고, 제품은 디자인 결정을
프로젝트 안에서 정해 기록하기로 했다. 외부 베타 전에는 Finder, Dock과 권한
화면에서 식별 가능한 앱 아이콘이 필요하다. 일정 앱이라는 사실뿐 아니라
KaosCal의 Event Brief와 Todo 흐름도 한눈에 드러나야 한다.

Apple의 현재 [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons)는
macOS 아이콘에 square 원본을 사용하고 최신 시스템이 일관된 rounded mask를
적용하는 방식을 설명한다. 하지만 KaosCal의 최소 지원 버전인 macOS 14/15의
legacy `.icns`가 같은 mask를 적용한다고 가정할 수는 없다. 핵심 표식은 작은
Finder/Dock 크기와 신·구 렌더 경로 모두에서 남아야 한다.

## 결정

- 핵심 표식은 `calendar grid + layered schedule blocks + checkmark`다. 캘린더
  탐색과 눈에 보이는 Todo를 한 표식 안에 결합한다.
- 배경은 midnight navy, 기존 앱 accent에 맞춘 steel blue, calendar는
  off-white, 완료 동작은 warm apricot 하나로 구분한다.
- 글자, 날짜 숫자와 실제 서비스의 로고는 넣지 않는다. locale·현재 날짜에
  종속되지 않고 Apple Calendar, BusyCal, Fantastical, Outlook의 표식을
  복제하지 않는다.
- 1024×1024 square master의 핵심 요소를 중앙 70% 안에 둔다. legacy macOS를
  위해 canvas edge까지 닿는 full-bleed squircle과 투명 corner를 원본에
  포함하되, 별도 margin이나 두 번째 rounded frame을 만들지 않아 최신
  system mask와 겹쳐도 작아 보이지 않게 한다.
- macOS 14 baseline과 현재 Xcode asset catalog를 위해 16, 32, 64, 128,
  256, 512, 1024px alpha PNG를 `AppIcon.appiconset`에 제공한다. 1024px
  master는 `AppIcon-512@2x.png`다.
- 현재는 단일 flattened design을 모든 크기에 사용한다. 외부 배포 polish에서
  Icon Composer의 layered/default·dark·tinted variant를 추가할 수 있지만
  핵심 calendar/check silhouette과 색 역할은 유지한다.

## 결과

별도 사용자 브랜드 입력 없이도 KaosCal을 Finder와 Dock에서 식별할 수 있고,
캘린더와 Todo라는 제품 범위를 동시에 전달한다. alpha fallback은 legacy
`.icns`의 각진 opaque square 위험을 줄인다. 작은 크기별 수작업 hinting과
Icon Composer variant는 아직 없으므로 macOS 14/15/최신 clean-machine
beta에서 Dock/Finder, light/dark wallpaper와 접근성 contrast를 다시 확인한다.
