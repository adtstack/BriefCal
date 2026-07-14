# Phase 10 Completion Blockers

> 기준 시각: 2026-07-12, Asia/Seoul
>
> 원칙: 구현·자동·offscreen·ad-hoc Release와 실제 외부 beta 배포를 분리한다. 실행하지
> 않은 항목은 통과로 올리지 않는다.

## 저장소 안에서 완료한 범위

- first-run onboarding, `⌘R` reload와 Day/Week empty-period 안내
- failed-bootstrap strict same-schema backup 선택, preflight-before-touch, failed SQLite
  file-family quarantine, replacement 재오픈과 실패 rollback
- onboarding/recovery offscreen bitmap, bootstrap success/no-touch/rollback 자동 회귀
- direct-distribution runbook, privacy/security/known-issues/user guide, beta-license placeholder
- 전체 Debug suite와 ad-hoc hardened-runtime Release audit

## 외부 beta를 차단하는 필수 항목

| Blocker | 필요한 입력/환경 | 닫힘 증거 |
| --- | --- | --- |
| Developer ID | Apple Team, Developer ID Application certificate/private key | exact archive/export signature leaf, secure timestamp, strict codesign |
| Notarization | validated notarytool Keychain profile와 network | Accepted submission/log, stapled app/package, Gatekeeper pass |
| Package/download | 승인된 ZIP/DMG 형식과 HTTPS 위치 | immutable checksum, quarantine을 유지한 실제 재다운로드 |
| License/legal | publisher, jurisdiction, EULA, beta term, refund/warranty/liability 결정 | [BETA-LICENSE.md](../BETA-LICENSE.md)를 승인 문서로 교체 |
| Contacts | support, privacy, security와 rollback 공지 경로 | 실제 접근 가능한 비공개/공개 연락 채널과 문서 반영 |
| Clean user | macOS 14와 현재 macOS의 별도 표준 사용자 | 설치→Gatekeeper→onboarding→권한 거부/복구→핵심 demo record |
| Accessibility | 실제 창, keyboard, VoiceOver, contrast/motion 설정 | focus order, label/action, clipping과 escape/default action record |
| Bootstrap live fault | 복제한 test user의 손상 DB와 current-schema backup | invalid no-touch, DB/sidecar quarantine, restore/relaunch, cleanup record |
| EventKit live matrix | 전용 Exchange Editor/Viewer와 비민감 fixture | 남은 all-day/time-zone/recurrence/move/read-only gate와 residue 0 |
| Local Data mutation | 복제한 test data와 실제 file panel | export/import/reset, recovery ZIP, real rollback-fault record |

## 이번 checkpoint의 미흡·관찰

- 중간 ad-hoc Release의 첫 실창에서 onboarding Continue 버튼이 가로로 밀려 보이지 않는
  문제를 발견해 별도 행으로 수정했다.
- 같은 중간 smoke에서 scene teardown이 sheet binding setter를 호출해 명시적 Continue
  없이 onboarding 완료가 저장될 수 있음을 발견했다. 완료 저장을 버튼 action에만
  연결했다.
- 수정 뒤 전체 suite와 최종 Release build/audit는 통과했지만, 동일 bundle identifier의
  기존 Xcode dev process가 accessibility window를 소유해 최종 CDHash build의 실창을
  다시 관찰하지 못했다. 해당 process는 사용자 상태일 수 있어 강제 종료하지 않았다.
- bootstrap recovery main/Settings UI는 offscreen bitmap까지만 확인했다. 실제 손상
  sandbox DB를 교체하는 UI smoke는 운영 DB 보호를 위해 별도 test user가 필요하다.
- power loss, process kill의 정확한 file-move window와 rollback 자체가 권한/디스크 오류로
  실패하는 조건은 자동 fault fixture가 없다.
- 실행 중 local store failure에는 살아 있는 writer 밑의 파일 교체를 열지 않도록
  `contextStore == nil` gate와 회귀를 추가했다. 이 runtime lock 화면의 실창/지원 절차는
  final accessibility smoke에 포함해야 한다.
- 자동 suite의 EventKit test 한 건은 read-only opt-in manual gate라 의도적으로 skip된다.

## 유지 규칙

- 이 문서는 blocker가 닫힐 때 run ID, exact artifact/CDHash, 환경, 결과와 cleanup을 추가한다.
- [Current Status](current-status.md)는 요약만 갱신하고, 상세 실행은
  [Implementation Log](implementation-log.md)와 이 문서에 보존한다.
- credential, account/email, raw calendar/event identifier, 실제 Event Brief 본문과 backup
  ZIP은 기록하거나 공개 issue에 첨부하지 않는다.
