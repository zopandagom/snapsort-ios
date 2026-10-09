---
name: verify
description: SnapSort 변경 사항을 lint → 빌드 → 테스트 순서로 로컬 검증하고 실패 원인을 요약한다. 코드 수정을 마쳤을 때, 커밋이나 PR 을 만들기 전에, 또는 사용자가 "검증", "테스트 돌려", "빌드 확인"을 요청할 때 사용한다.
context: fork
agent: general-purpose
model: sonnet
---

# verify

CI(`.github/workflows/ci.yml`)와 같은 Makefile 타깃으로 검증한다. 로컬에서 통과하면 CI 에서도 통과해야 한다.

서브에이전트로 실행된다. 빌드 로그는 여기서 소화하고, 호출한 쪽에는 **아래 보고 형식만** 돌려준다. 로그 원문을 붙여 넣지 않는다.

## 순서

1. **Lint** — `make lint`
   - 실패하면 `make format` 을 한 번 실행한 뒤 다시 `make lint` 를 실행한다.
   - 그래도 남는 오류는 대부분 아키텍처 규칙(`.swiftlint.yml` 의 `custom_rules`)이다. 억제 주석(`swiftlint:disable`)을 달지 말고 docs/ARCHITECTURE.md 에 맞게 코드를 고친다.
2. **Build & Test** — `make test` (timeout 은 10분으로 넉넉하게)
   - 모든 모듈의 테스트가 `SnapSort-Workspace` 스킴 하나로 실행된다.
3. **실패 분석**
   - 컴파일 오류는 xcbeautify 출력의 `error:` 줄만 보면 된다.
   - 테스트 실패는 결과 번들에서 요약을 읽는다.
     ```bash
     xcrun xcresulttool get test-results summary --path build/TestResults.xcresult \
       | jq '{result, totalTestCount, failedTests, testFailures}'
     ```
   - 시뮬레이터를 못 찾으면 `xcrun simctl list devices available | grep iPhone` 으로 확인하고
     `make test DESTINATION='platform=iOS Simulator,name=<기기>,OS=latest'` 로 다시 실행한다.

## 보고 형식

- 통과: `lint ✓ · build ✓ · test ✓ (N개)` 한 줄.
- 실패: 단계, 파일:줄, 원인 한 줄, 수정 방향. 고쳤다면 무엇을 고쳤는지와 재실행 결과.
- 실패를 숨기거나 테스트를 건너뛰어 통과시키지 않는다. 테스트를 삭제하거나 `.disabled` 로 바꿔야 할 것 같으면 먼저 사용자에게 묻는다.
