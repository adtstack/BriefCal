# T5 — Notes / reference layer

> 상태: implemented / live pending — URL reference-only persistence·Event Brief UI·backup/reset 완료
> 선행: T0 보안·연결 모델, 실제 provider별 privacy review

## 목표

task provider와 참고자료(notes/reference)를 같은 entity로 합치지 않고, Event Brief에서
외부 자료로 안전하게 이동할 수 있는 최소 reference 계층을 결정한다.

## 우선 범위

1. 외부 note/page URL을 Event Brief context에 reference로 첨부
2. provider와 account, 마지막 확인 시각, 표시 제목만 최소 캐시
3. Task Center에는 reference를 task로 변환하지 않고 별도 섹션으로 표시
4. Notion은 page URL/reference부터 검토하고 database 양방향 sync는 약속하지 않음
5. Google Keep은 일반 사용자의 공식 양방향 API 범위가 확인될 때까지 보류

## 하지 않을 것

- 외부 notes 전체를 SQLite와 ZIP에 자동 복사
- notes를 task로 자동 변환하거나 완료 상태를 추측
- provider의 문서·프로젝트·권한 모델을 KaosCal 안에 복제
- 사용자가 확인하지 않은 외부 본문을 Calendar event notes에 쓰기

## 연결 모델

```text
context
  └─ reference(id, provider, account, remote_id, url, title_cache, state)
```

## 현재 구현

- `v6_context_references`는 context별 URL reference metadata만 보관한다.
- provider(`web`/`notion`), HTTP(S) URL, 제목 cache, state, last-checked 시각만 저장한다.
  원격 page 본문, OAuth token, credential은 SQLite와 backup에 넣지 않는다.
- reference는 context 삭제 시 함께 제거되고, local data reset·backup/restore의 같은
  transactional boundary에 포함된다.
- Event Brief에서 reference를 추가·삭제·열 수 있다. Reference는 task destination이나
  provider task로 변환되지 않는다.

reference state는 `active`, `missing`, `permissionRequired`, `disconnected`로 제한한다.
원격 page 삭제는 reference를 조용히 제거하지 않고 missing으로 표시한다. URL이 provider
deep link로 열리지 않으면 웹 URL 또는 “provider에서 열기” fallback을 제공한다.

## 검증 계획

- reference 추가·삭제·재연결이 Calendar 원본과 local task에 영향을 주지 않는지
- account disconnect와 token revoke 뒤 URL·cache·metadata 처리
- backup에 token과 원격 본문이 포함되지 않는지
- provider page 권한 없음·삭제·redirect 실패
- Event Brief에서 reference가 task destination badge와 혼동되지 않는지
- 실제 clean account에서 link open과 cleanup

## 종료 게이트

공식 API와 개인정보 경계를 충족하는 provider만 reference 대상으로 채택한다. 조건이
충족되지 않으면 T5는 구현하지 않고 “URL reference only” 또는 “보류”로 종료한다.
양방향 notes sync를 도입하려면 별도 제품 결정과 ADR이 필요하다.
