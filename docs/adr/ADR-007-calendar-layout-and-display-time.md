# ADR-007: 캘린더 배치와 표시 시간 의미

> 상태: Accepted
> 날짜: 2026-07-10
> 관계: ADR-003을 구체화하며 대체하지 않음

## 배경

Day, Week, Agenda가 같은 EventKit snapshot을 사용해도 날짜 경계, DST, 짧은 일정, 반복 occurrence 식별을 서로 다르게 해석하면 일정이 사라지거나 겹친다. 특히 EventKit 종일 일정의 raw `endDate`는 생성·정규화 경로에 따라 다음 날 자정 또는 마지막 날 `23:59:59`로 관찰될 수 있어 UI에서 그대로 사용할 수 없다.

## 결정

- Day는 표시 달력 기준 1일, Week와 Agenda는 같은 기준의 7일을 사용한다.
- 모든 표시 범위와 일정 교차 판정은 반개구간 `[start, end)`으로 계산한다.
- 시간 일정은 표시 달력의 현지 자정에서 분할하고, 자정에 끝나는 일정은 다음 날 segment를 만들지 않는다.
- 종일 일정은 provider 경계에서 시작일 자정과 배타 종료일 자정으로 정규화한다. raw end가 날짜 중간이나 `23:59:59`면 그 날짜의 다음 날 자정으로 올리고, 이미 자정이면 그대로 사용한다.
- Day/Week 시간축은 DST 날짜에도 `0...1,440`분의 고정 24시간 wall-clock 축이다. spring-forward의 없는 시각은 비어 있고, fall-back의 두 동일 현지 시각은 같은 y 위치에서 겹침 column으로 구분한다.
- 짧은 일정은 원본 시간을 바꾸지 않고 배치에만 최소 24분 높이를 사용한다. 자정 근처에서는 카드 전체가 보이도록 visual start를 위로 이동하며 같은 visual interval로 충돌도 계산한다.
- 겹침은 날짜별 결정적 greedy column 배치로 계산한다. 맞닿기만 하는 일정은 새 그룹이고, 고밀도에서는 날짜 열 너비를 늘려 가로 스크롤한다.
- 종일 영역은 실제 행 수에 맞춰 늘리되 화면 높이의 35%, 최대 240pt에서 내부 세로 스크롤로 전환한다.
- all-day와 floating은 원래 calendar identifier를 가진 local components로 snapshot하고, 표시 calendar의 time zone에서 재구성한다. zoned 일정은 절대 시점을 유지한다.
- UI용 occurrence ID는 calendar identifier와 `external → calendar item → event` 식별자, 반복 occurrence anchor로 만든다. 이는 Phase 3의 영속 Event Brief 재연결 순서와 목적이 다른 임시 표시 ID다.
- EventKit의 calendar color는 값 snapshot으로 UI에 전달해 narrow rail에만 사용한다. 사용자가 지정할 calendar role과 색 override는 Phase 8 범위다.

## 결과

- Day/Week/Agenda가 같은 visible period와 명시적 display calendar를 공유한다.
- 레이아웃 계산은 Foundation 값 타입이며 SwiftUI 좌표와 분리해 DST·경계·겹침을 단위 테스트할 수 있다.
- 초기 조회 범위를 벗어나 이동하면 현재 화면을 포함하는 새 범위를 가져오고, 빠르게 되돌아오면 오래된 pending 조회를 취소한다.
- 실제 Exchange의 종일·DST·반복 동작은 자동 모델 테스트만으로 지원 완료를 선언하지 않고 `KC-E2`~`KC-E4` 실계정 결과로 확정한다.

## 검토한 대안

- 실제 경과 시간에 따라 DST 날짜를 23시간 또는 25시간 높이로 표시: Week의 날짜 열이 서로 다른 축을 가져 비교가 어려워 채택하지 않았다.
- 카드에 최소 높이만 주고 실제 구간으로 column 계산: 짧은 카드가 시각적으로 겹쳐 채택하지 않았다.
- raw EventKit all-day end를 항상 배타 종료로 간주: 로컬 SDK 재현에서 `23:59:59`가 관찰되어 채택하지 않았다.

## 남은 검증

- macOS full calendar access와 `KAOS-TEST`의 실제 EventKit 노출
- Exchange backend 종류
- Exchange `KC-E2` 종일·다일, `KC-E3` DST, `KC-E4` 반복 occurrence
- 실제 창에서의 키보드·VoiceOver·스크롤 상호작용
