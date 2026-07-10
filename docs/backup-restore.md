# Backup And Restore

## 목표

KaosCal은 local-first 앱이므로 사용자의 Event Brief와 Task Center 데이터는 이 Mac의 SQLite DB에 있다.
백업/복원 기능은 구독 없는 제품에서 신뢰를 만드는 핵심 기능이다.

## 원칙

- 원본 캘린더 이벤트는 backup에 포함하지 않는다.
- Event Brief, event task, personal task, 변경 기록 등 KaosCal local data만 backup한다.
- Export는 사용자가 읽을 수 있는 zip 파일로 만든다.
- Import는 기존 DB를 경고 없이 덮어쓰지 않는다.
- schema version이 맞지 않으면 안전하게 중단한다.

## Export 형식

```text
KaosCal-Backup-YYYY-MM-DD-HHMM.zip
├─ kaoscal.sqlite
└─ manifest.json
```

`manifest.json`:

```json
{
  "app_version": "1.0.0-beta.1",
  "schema_version": 1,
  "exported_at": "2026-07-10T00:00:00Z",
  "source": "KaosCal",
  "contains_calendar_events": false,
  "contains_event_briefs": true
}
```

## Export UX

Settings에서 사용자가 직접 backup을 만든다.
성공 후 파일 위치를 보여준다.

사용자 문구:

```text
이 백업에는 KaosCal 체크리스트, 개인 할 일, 메모, 변경 기록만 포함됩니다.
원본 캘린더 일정은 기존 캘린더 계정에 그대로 남아 있습니다.
```

## Import v1 방식

v1은 record-level merge를 하지 않는다.
안전한 첫 버전은 "현재 DB를 자동 백업한 뒤 가져온 DB로 교체" 방식이다.

절차:
1. zip 구조와 manifest 확인
2. schema_version 호환성 확인
3. 현재 DB를 자동 backup 위치에 복사
4. 앱의 DB 연결 종료
5. 가져온 DB로 교체
6. 앱 상태 재로드
7. EventKit 이벤트와 context 재연결 시도

## Import 금지 사항

- 경고 없이 현재 DB 덮어쓰기
- 원본 캘린더 이벤트 생성/삭제
- schema가 더 높은 backup을 강제로 import
- 손상된 zip을 부분 import

## Reset Local Data

Settings에서 KaosCal local data만 삭제할 수 있어야 한다.
이 기능은 원본 Calendar 이벤트를 삭제하지 않는다.

필수 확인 문구:

```text
이 작업은 KaosCal의 체크리스트, 개인 할 일, 메모, 변경 기록을 이 Mac에서 삭제합니다.
기존 캘린더 계정의 일정은 삭제되지 않습니다.
```

## 자동 백업 후보

v1에서는 수동 backup을 우선한다.
다음 상황에서는 자동 backup을 검토한다.

- migration 전
- import 전
- reset local data 전
- beta build 업그레이드 전

## 복구 전략

문제 상황:
- DB 파일이 없음: 새 DB 생성, 사용자에게 local context가 없다고 안내
- DB 파일 손상: 읽기 전용 복구 시도 또는 backup import 안내
- migration 실패: 앱 시작 중단, 기존 DB 보존, backup 생성 안내
- import 실패: 기존 DB 유지

## 테스트 기준

- export zip 생성
- manifest 값 확인
- 새 DB로 import 성공
- import 후 Event Brief 조회 성공
- reset local data 후 원본 캘린더 이벤트 유지
- 손상된 zip import 실패 처리
- schema mismatch 실패 처리
