# QA Checklist

## QA 목표

KaosCal QA의 핵심은 예쁜 캘린더가 뜨는지보다 "사용자의 일정 맥락을 잃지 않는지"를 확인하는 것이다.
특히 Event Brief 데이터가 원본 calendar notes를 오염시키지 않는지, 일정 이동과 삭제에서 context가 살아남는지 반복 검증한다.

## 테스트 환경

최소 환경:
- 깨끗한 macOS 사용자 계정
- 기존 일정이 있는 개인 캘린더
- 읽기 전용 또는 subscription 캘린더
- 네트워크가 꺼진 상태
- 권한을 거부한 상태
- 앱 재설치 또는 DB 초기화 상태

## 수동 테스트 시나리오

### 1. 첫 실행과 권한 허용

절차:
1. 앱을 처음 실행한다.
2. 캘린더 권한 요청을 허용한다.
3. Agenda 또는 Week view를 확인한다.

기대 결과:
- 실제 macOS Calendar 일정이 표시된다.
- 캘린더 목록이 표시된다.
- 앱이 로컬 저장 정책을 명확히 설명한다.

### 2. 권한 거부

절차:
1. 앱을 처음 실행한다.
2. 캘린더 권한을 거부한다.
3. 메인 화면을 확인한다.

기대 결과:
- 빈 오류 화면으로 방치되지 않는다.
- 권한을 다시 허용하는 경로가 안내된다.
- local DB가 손상되거나 삭제되지 않는다.

### 3. Event Brief 저장

절차:
1. 기존 일정을 선택한다.
2. Before task를 추가한다.
3. After task를 추가한다.
4. notes를 작성한다.
5. 앱을 종료 후 재실행한다.

기대 결과:
- 체크리스트와 notes가 유지된다.
- 같은 원본 일정에 같은 Event Brief가 연결된다.
- Calendar.app의 원본 notes에는 KaosCal 체크리스트가 쓰이지 않는다.

### 4. 새 일정 생성

절차:
1. KaosCal에서 새 일정을 만든다.
2. Calendar.app을 연다.
3. 같은 일정이 보이는지 확인한다.

기대 결과:
- 새 일정이 EventKit을 통해 실제 캘린더에 저장된다.
- KaosCal Event Brief는 local DB에만 저장된다.
- writable calendar에만 생성할 수 있다.

### 5. 일정 이동

절차:
1. Event Brief가 있는 일정을 선택한다.
2. 시간을 변경한다.
3. Move confirmation을 확인한다.
4. 변경을 승인한다.

기대 결과:
- old time과 new time이 표시된다.
- 연결된 before/during/after tasks, notes, change history가 함께 유지된다는 설명이 보인다.
- 승인 후 context_id가 유지된다.
- event_change_log에 before_json과 after_json이 기록된다.

### 6. 이동 취소

절차:
1. Event Brief가 있는 일정을 이동하려고 한다.
2. Move confirmation에서 취소한다.

기대 결과:
- EventKit 이벤트가 변경되지 않는다.
- SQLite change log가 추가되지 않는다.
- Event Brief 상태가 바뀌지 않는다.

### 7. 읽기 전용 일정

절차:
1. subscription 또는 read-only calendar의 일정을 선택한다.
2. 편집 UI를 확인한다.

기대 결과:
- 원본 일정 편집 버튼이 비활성화된다.
- 왜 수정할 수 없는지 설명한다.
- KaosCal local Event Brief는 편집 가능해야 한다.

### 8. 원본 일정 삭제

절차:
1. Event Brief가 있는 일정을 Calendar.app에서 삭제한다.
2. KaosCal로 돌아온다.
3. 동기화 또는 새로고침 후 상태를 확인한다.

기대 결과:
- Event Brief가 즉시 삭제되지 않는다.
- context가 orphaned 상태로 표시된다.
- 사용자는 보관, 재연결, 삭제 중 선택할 수 있다.

### 9. Backup / Import

절차:
1. Event Brief가 있는 상태에서 backup export를 만든다.
2. local context를 초기화한다.
3. backup을 import한다.

기대 결과:
- Event Brief가 복구된다.
- 원본 캘린더 이벤트는 import 과정에서 삭제되지 않는다.
- schema version이 맞지 않으면 안전한 오류를 보여준다.

## 회귀 테스트 규칙

- Event Brief 데이터는 절대 `EKEvent.notes`에 serialize되지 않는다.
- read-only source에는 destructive edit control을 보여주지 않는다.
- local context 삭제는 원본 calendar event 삭제와 분리된다.
- import는 기존 DB를 경고 없이 덮어쓰지 않는다.
- 일정 이동 취소는 EventKit과 local DB 모두 변경하지 않는다.
- orphaned context는 사용자 선택 없이 자동 삭제하지 않는다.

## Unit test 후보

- EventContextRepository CRUD
- EventTaskRepository ordering
- EventTask completion persistence
- ChangeLogRepository append/query
- fingerprint normalization consistency
- EventIdentityResolver fallback order
- MoveEventUseCase confirmation required
- MoveEventUseCase context_id preservation
- Orphaned context transition

## Beta gate

외부 베타 전에 아래 조건을 모두 통과해야 한다.

- clean checkout에서 build 성공
- 첫 실행 권한 플로우 성공
- 실제 macOS Calendar 이벤트 표시
- 병원 일정 데모 end-to-end 성공
- 앱 재실행 후 Event Brief 유지
- 일정 이동 후 context 유지와 change log 기록
- 읽기 전용 일정 설명 표시
- backup export/import 성공
- local DB 삭제와 원본 일정 삭제가 분리되어 있음

## 버그 리포트 형식

```text
Title:
Environment:
Build:
Calendar account type:
Steps:
Expected:
Actual:
Notes:
Attachments:
```

