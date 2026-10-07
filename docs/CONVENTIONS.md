# 개발 규칙: 해야 할 것 / 하지 말아야 할 것

사람과 Claude 모두에게 적용된다. 표의 "강제" 열은 어디서 자동으로 막히는지다. 빈칸이면 리뷰에서 잡는다.

## 1. 아키텍처
| ✅ 해야 할 것 | ❌ 하지 말아야 할 것 | 강제 |
|---|---|---|
| Model 상태는 `public private(set) var` | View 나 다른 타입이 Model 상태를 직접 대입 | 컴파일러 |
| View 는 이벤트 메서드(`onAppear()`, `xxxTapped()`, `xxxChanged(_:)`)만 호출 | `$model.x` 양방향 바인딩 | `no_two_way_model_binding` |
| 외부 시스템은 Client 로 감싸고 Interface / Impl / Testing 으로 나눈다 | Feature 에서 `import Photos`, `import Vision`, `import SwiftData` 등 | `system_framework_only_in_impl` |
| Impl 은 App 에서만 만들어 주입 | Feature 나 Interface 에서 `import …Impl` | `impl_import_only_in_app` |
| Fake 는 Testing 모듈에 두고 Tests·Example 에서만 사용 | 프로덕션 코드에서 `import …Testing` | `testing_import_not_in_production` |
| `#Preview` 는 Feature 의 Example 타깃에 | Feature Sources 에 Fake 를 만들어 Preview 작성 | |
| Feature 끼리 필요한 공유는 Client 나 (W2 이후) Core 로 | Feature 가 다른 Feature 에 의존 | 템플릿 |
| 새 모듈은 `Module.swift` 의 enum 과 `Project.client/feature` 템플릿으로 | 매니페스트에서 `Target` 을 직접 만들거나 빌드 설정을 덮어쓰기 | |

## 2. Swift / 동시성
| ✅ | ❌ |
|---|---|
| Model 은 `@MainActor @Observable final class` | `ObservableObject` / `@Published` (구 방식) |
| Client 프로토콜은 `Sendable`, 입출력도 `Sendable` 값 타입 | `@unchecked Sendable`, `nonisolated(unsafe)` 로 경고 숨기기 (불가피하면 이유를 주석으로) |
| 무거운 동기 작업(PhotoKit 조회, OCR)은 Impl 에서 `@concurrent` 로 메인 밖에서 | Model 에서 `Task.detached` 로 우회 |
| 에러는 Interface 에 도메인 에러 타입으로 정의해 던진다 | Feature 에 `PHPhotosError`, `VNError` 같은 프레임워크 에러가 새어 나오기 |
| 강제 언래핑 대신 `guard let` / 기본값 | `!`, `try!` (테스트 제외) |
| 명시적 `self.` (SwiftFormat 이 자동 삽입) | |

## 3. 테스트
| ✅ | ❌ |
|---|---|
| Swift Testing(`import Testing`, `@Test("한국어 설명")`, `#expect`) | 새 테스트를 XCTest 로 작성 |
| Model 의 모든 public 이벤트 메서드에 테스트: Fake 주입 → 이벤트 호출 → 상태 검증 | View 를 스냅샷/UI 테스트로만 검증 |
| Client Impl 은 순수 로직(매핑, 파싱, 규칙 분류)을 분리해 `@testable` 로 테스트 | 실제 사진 보관함·권한 팝업에 의존하는 테스트 |
| OCR·분류 정확도는 `Fixtures/` 의 샘플 스크린샷으로 회귀 테스트 (W2) | 개인 사진을 픽스처로 커밋 (직접 만든 샘플만) |
| Foundation Models 테스트는 `.enabled(if: SystemLanguageModel.default.isAvailable)` 로 조건부 | CI 에서 모델 없다고 실패하는 테스트 |
| 실패하는 테스트는 고친다 | 테스트 삭제·`.disabled` 로 통과시키기 (필요하면 먼저 합의) |

## 4. 개인정보 (제품의 핵심 약속)
| ✅ | ❌ | 강제 |
|---|---|---|
| 모든 분석은 기기 안에서 | `URLSession` 등 네트워크 코드 추가 (필요하면 사전 합의 후 별도 모듈) | `no_network` |
| 로그에는 개수·소요 시간·카테고리 같은 메타데이터만 | OCR 텍스트, 기프티콘 번호, 사진 식별자를 `print`/`Logger` 로 출력 | |
| `Logger` 는 `privacy: .private` 기본 | 서드파티 분석/크래시 SDK 를 합의 없이 추가 | |
| 권한은 필요한 시점에 요청하고 제한 접근(`.limited`)도 정상 흐름으로 처리 | 앱 시작 즉시 권한 팝업 | |

## 5. Git / PR
| ✅ | ❌ | 강제 |
|---|---|---|
| 작업 하나 = 브랜치 하나: `feat/w1-photo-onboarding`, `fix/…`, `chore/…` | main 직접 커밋·push | Claude 훅, git pre-push 훅 |
| 커밋 메시지: `<type>: <한국어 요약>` (아래 마이크로 커밋 표의 type) | 여러 작업을 한 PR 에 섞기 | |
| 커밋 전에 수정한 Swift 파일(스테이지 여부 무관, 커밋될 내용 포함) lint 통과 (`make format` 으로 수정) | lint 실패 상태로 커밋 | git pre-commit 훅, CI Danger |
| PR 전에 `make lint && make test` (또는 `/verify`) | CI 실패 상태로 머지 | |
| UI 변경은 PR 에 스크린샷(선택) | force push 로 main 이력 변경 | settings deny |
| 머지는 **Rebase merge** (마이크로 커밋 이력을 main 에 그대로 남긴다) | Squash merge (커밋 단위가 사라진다) | |
| | `.xcodeproj` / `.xcworkspace` 커밋 | `.gitignore` |

### 마이크로 커밋
작업은 **역할별로 구현 → 검증**하고, 커밋은 **사용자가 지시할 때** 역할별로 나눠서 한다. 한 번에 몰아서 커밋하지 않는다.

| type | 역할 | 예 | 커밋 전 검증 |
|---|---|---|---|
| `build` | 도구 버전, Tuist 템플릿, Makefile | `.mise.toml`, `Tuist/`, `Makefile` | `make generate` (+ `make test` 영향 시) |
| `feat` / `fix` / `refactor` | 코드 구현 (**해당 테스트 포함**) | `Projects/**` | `make lint && make test` |
| `test` | 기존 코드에 테스트만 추가 | `Projects/**/Tests` | `make test` |
| `style` | 포맷·lint 설정과 그에 따른 일괄 포맷 | `.swiftformat`, `.swiftlint.yml` | `make lint` |
| `ci` | GitHub Actions, PR 템플릿, dependabot, Danger | `.github/**`, `Gemfile*`, `Dangerfile` | YAML 문법, 참조하는 make 타깃·경로 존재 |
| `docs` | 문서 | `docs/**`, `README.md` | 링크·코드·경로가 실제와 일치 |
| `chore` | 하네스(Claude Code, git 훅) | `CLAUDE.md`, `.claude/**`, `.githooks/**` | 훅 스크립트를 입력 JSON 으로 직접 실행해 확인 |

- 커밋 하나 = 목적 하나. 요약에 "그리고"가 들어가면 나눈다.
- **모든 커밋 시점에서 빌드와 테스트가 통과해야 한다.** 중간 커밋이 깨지면 `git bisect` 와 되돌리기가 불가능해진다.
- 구현과 그 구현의 테스트는 같은 커밋에 넣는다 (테스트 없는 구현 커밋 금지).
- 순서는 의존 방향을 따른다: 도구·빌드 → 코드 → lint 설정 → CI → 문서 → 하네스.
- 기능 코드도 잘게 나눈다: Client Interface + Fake → Feature Model + 테스트 → View·Example → Impl + 테스트 → App 연결.

## 6. Claude Code 작업 방식
- 작업 시작 전 DEVELOPMENT_PLAN 의 해당 주차 목표와 이 문서들을 확인한다.
- 구조를 바꾸는 결정(새 외부 의존성, 모듈 종류 추가, 네트워크, 아키텍처 규칙 변경)은 먼저 제안하고 합의한 뒤 진행한다. 합의되면 이 문서와 ARCHITECTURE.md 를 같은 PR 에서 갱신한다.
- 로컬 빌드·테스트는 자유롭게 실행한다 (`make test`).
- 역할 하나를 마칠 때마다 `/verify` → `/arch-review` 로 검증하고 멈춘다. **커밋(`/micro-commit`)과 PR(`/pr`)은 사용자가 지시할 때만** 실행한다.
- `/arch-review` 의 🔴 필수 항목을 남긴 채 커밋하거나 PR 을 만들지 않는다.
- lint 오류를 `// swiftlint:disable` 로 숨기지 않는다.
- 사용자가 요청하지 않은 리팩터링이나 범위 확장은 하지 않는다. 발견한 문제는 보고한다.
