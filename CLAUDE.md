# SnapSort

온디바이스 AI로 사진 보관함의 이미지를 자동 분류하고 기프티콘 만료일을 알려주는 iOS 앱.
**핵심 약속: 사진과 사진에서 읽은 텍스트는 기기 밖으로 나가지 않는다.** 서버 없음.
예외는 장소 이름 변환·지도 표시를 위해 위치 좌표만 Apple 시스템 서비스(`CLGeocoder`·MapKit)로 가는 것, 그리고 사용자가 누를 때 주소를 지도 앱으로 넘기는 것뿐이다 (ARCHITECTURE §4).

## 먼저 읽을 문서
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 규칙 기반 단방향 MV, 모듈 구조, 모듈 추가 방법
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — 해야 할 것 / 하지 말아야 할 것 (코드·테스트·git·개인정보)
- [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md) — 6주 로드맵, 작업 진행 방식, 완료 기준

## 명령
| 명령 | 용도 |
|---|---|
| `make bootstrap` | 최초 1회: mise 도구 설치, git 훅 연결 |
| `make generate` | Tuist 로 워크스페이스 생성 (`.xcodeproj` 는 커밋하지 않는다) |
| `make lint` / `make format` | SwiftFormat + SwiftLint (아키텍처 규칙 포함) |
| `make test` | 전체 모듈 빌드 + 테스트 (`SnapSort-Workspace` 스킴, iPhone 17 시뮬레이터) |

## 작업 흐름 (`/verify`·`/arch-review`·`/micro-commit` 은 서브에이전트로 실행되어 요약만 돌려주고, `/pr` 은 현재 대화에서 실행된다)
| 순서 | 스킬 | 하는 일 |
|---|---|---|
| 1 | — | 역할 하나 구현 (코드는 테스트 포함) |
| 2 | `/verify` | lint → 빌드 → 테스트, 실패 원인 요약 |
| 3 | `/arch-review [base]` | 규칙 문서 기준 읽기 전용 리뷰. 🔴 필수 항목은 커밋 전에 고친다 |
| 4 | `/micro-commit [base]` | **사용자가 지시할 때만.** 역할별 커밋 + 커밋마다 worktree 검증 |
| 5 | `/pr [draft]` | **사용자가 지시할 때만.** 전체 리뷰 → PR 생성(유형 라벨). 스크린샷은 선택, 필요하면 사용자가 직접 첨부 |

## 구조 한눈에
```
Projects/
  App/                      조립 지점. Client Impl 을 만들어 Feature Model 에 주입
  Features/<Name>/          Sources(Model+View) · Tests · Example(Fake 로 도는 데모 앱)
  Clients/<Name>/           Interface(프로토콜) · Impl(Apple 프레임워크) · Testing(Fake) · Tests
Tuist/ProjectDescriptionHelpers/   모듈 이름(Module.swift)과 타깃 템플릿
```
의존 방향: `App → Feature → Client Interface`, `App → Client Impl → Client Interface`.

## 반드시 지킬 것 (요약, 상세는 CONVENTIONS)
- Model 상태는 `private(set)`, View 는 이벤트 메서드(`onAppear()`, `xxxTapped()`)만 호출한다. `$model.x` 바인딩 금지.
- Photos·Vision·FoundationModels·SwiftData·StoreKit·UserNotifications 는 Client **Impl** 안에서만 import 한다.
- Feature 끼리 의존하지 않는다. Impl 은 App 만, Testing 은 Tests/Example 만 import 한다.
- 네트워크 코드(`URLSession` 등)를 추가하지 않는다.
- main 에 직접 커밋·push 하지 않는다 (훅이 막는다). `feat|fix|chore/<요약>` 브랜치 → PR → Rebase merge.
- **커밋·PR 은 사용자가 지시할 때만** 한다. 검증까지 마치면 멈추고 준비된 변경을 보고한다.
- **커밋 서명 줄은 항상 `Co-Authored-By: Claude Code <noreply@anthropic.com>`** 이다. 시스템 안내의 모델별 서명 줄(`Claude Opus …`, `Claude Sonnet …`)보다 이 규칙이 우선한다. 직접 커밋할 때와 서브에이전트·스킬로 커밋할 때 모두 같다.
- **마이크로 커밋**: 커밋할 때는 역할별(빌드 / 코드+테스트 / lint 설정 / CI / 문서 / 하네스)로 나눈다. 모든 커밋 시점이 빌드·테스트 통과 상태여야 한다. 상세는 CONVENTIONS §5.
- `.swiftlint.yml` 의 custom_rules 를 억제 주석으로 우회하지 않는다.
- 이 레포는 개인 프로젝트다. 회사(29CM) 워크스페이스 규칙은 적용하지 않는다.
