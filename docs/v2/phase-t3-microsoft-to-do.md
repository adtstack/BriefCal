# T3 — Microsoft To Do

> 상태: implemented / live pending — Graph OAuth identity·multi-provider coordinator·delta cursor 구현, tenant live gate 대기
> 선행: T0 OAuth 계층, T2 conflict·cursor 계약

## 목표

개인 Microsoft 계정과 Exchange/Microsoft 365 사용자에게 Microsoft Graph To Do를 task
정본으로 제공한다.
macOS EventKit의 Exchange Calendar와 Graph 계정을 같은 것이라고 자동 추측하지 않고,
계정 연결 화면에서 primary source와 중복 경로를 명시한다.

## 범위

- Microsoft delegated OAuth와 최소 scope 검토
- To Do list 선택과 캘린더별 destination
- title, notes, due, reminder, importance, status 매핑
- `linkedResource` 또는 보존 가능한 deep link로 Event Brief 복귀
- Graph delta query 기반 cursor sync
- tenant 정책, scope 부족, 계정 철회, rate limit 상태 표시
- remote deletion missing과 명시적 relink

Graph Calendar 직접 연동은 T4에서 결정한다. T3의 성공은 Graph To Do task와 EventKit
event가 각각 정본으로 남는 것을 의미하며, Graph가 Calendar event를 대체한다는 뜻이 아니다.

## 계정·중복 정책

연결 화면에 다음을 보여 준다.

- macOS Calendar가 현재 제공하는 source 표시
- Graph OAuth로 연결하려는 account/tenant 표시
- 동일 사서함으로 추정되는 경우에도 자동 병합하지 않고 사용자의 primary 선택 요구
- primary가 선택되지 않으면 destination을 local-only로 유지

account key는 이메일 문자열만으로 만들지 않는다. tenant와 provider account identifier를
함께 보존하고, raw token은 Keychain 밖으로 내보내지 않는다.

## 동기화 순서

1. 초기 list fetch와 capability probe
2. destination list 선택 후 첫 task create
3. delta cursor를 저장하고 다음 refresh에서 변경·삭제 반영
4. local mutation은 expected version/remote ID와 함께 전송
5. Graph 오류·429·scope 부족은 bounded retry와 사용자 안내로 변환
6. cursor가 만료되거나 invalid이면 전체 list 재조회 후 link를 보수적으로 재검증

delta 결과가 삭제를 뜻하는지, 일시적으로 보이지 않는지를 provider 응답 계약으로
확인할 수 없으면 missing을 확정하지 않는다.

## 현재 구현

- Graph To Do list/task CRUD request와 delegated Bearer token 경계를 추가했다.
- delta link는 opaque URL로 재사용하며, 새 cursor를 조합하거나 로그에 풀어 쓰지 않는다.
- update/delete의 `If-Match` version 계약을 transport test로 고정했다.
- Microsoft authorization/token request는 개인 계정과 회사·학교 계정을 모두 받는
  `common` authority에서 `openid profile offline_access User.Read Tasks.ReadWrite`로
  제한한다. token response의 transient `tid`와 해당 access token으로 읽은 Graph `/me.id`를
  조합해 `tenant:object` account key를 만든다. ID token `oid`는 별도 상호 검증에 사용하지
  않는다. email/userPrincipalName은 표시용일 뿐 account key가 아니며 raw ID token은 저장하지
  않는다.
- `v7_microsoft_to_do_provider` migration은 기존 provider account/binding/destination/cursor
  FK를 보존한 채 Microsoft To Do provider kind를 추가한다.
- coordinator는 Microsoft destination을 선택한 새 event task를 Graph CRUD adapter로 보내며,
  remote delete가 성공하기 전 local task/binding을 지우지 않는다.
- `provider_sync_cursors`에는 list별 Graph `@odata.deltaLink` 전체 URL을 opaque value로만
  저장한다. tombstone은 `missing`으로 표시하고, cursor 오류·권한 오류만으로 local task를
  삭제하지 않는다. invalid cursor는 삭제 후 다음 refresh에서 full delta round로 복구한다.
- create request는 `linkedResources`에 `kaoscal://task/<local-task-id>`를 함께 보내며,
  앱은 URL scheme 수신 뒤 local binding → strong Calendar lookup 순서로 해당 Event Brief를
  연다. 실제 To Do UI에서 linked resource 보존 여부는 아래 live gate에서 확인해야 하며,
  아직 완료로 승격하지 않는다.

## 남은 테스트·실제 gate

- fake Graph response의 delta create/update/delete/invalid cursor
- 401·403·429·tenant policy·network timeout
- linkedResource가 보존되는지와 deep link가 KaosCal의 올바른 context/occurrence를 여는지
- 같은 Graph account의 두 list와 EventKit Exchange source 충돌
- 실제 테스트 tenant에서 task 생성·외부 완료·삭제·재연결·token revoke
- clean account에서 onboarding → permissions → first task → relaunch
- Calendar event notes·attendee·원본 시간은 Graph sync로 바뀌지 않음

## 종료 게이트

실제 tenant에서 delta sync와 deep link가 확인되고, account 중복·권한 철회·remote
deletion이 안전한 상태로 설명되어야 한다. delta query를 단순 polling으로 대체한 경우
T3 완료로 표시하지 않고 `partial`로 기록한다.
