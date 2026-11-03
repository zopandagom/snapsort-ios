# SnapSort

온디바이스 AI로 사진 보관함의 이미지를 자동 분류하고 기프티콘 만료일을 알려주는 iOS 앱.
**핵심 약속: 사진과 사진에서 읽은 텍스트는 기기 밖으로 나가지 않는다.** 서버 없음.
예외는 장소 이름 변환·지도 표시를 위해 위치 좌표(와 언어·지역 설정)만 Apple 시스템 서비스(MapKit 지오코딩·지도. 사용자가 지도를 움직이면 그 영역의 지도 요청도)로 가는 것, 사용자가 누를 때 주소를 지도 앱으로 넘기는 것, 그리고 사용자가 누를 때 개인정보 처리방침 웹 페이지(GitHub Pages)를 기본 브라우저로 여는 것(앱이 보내는 데이터 없음)뿐이다 (ARCHITECTURE §4).
Debug 빌드 전용 개발 도구는 CONVENTIONS §4.

## 먼저 읽을 문서
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 규칙 기반 단방향 MV, 모듈 구조, 모듈 추가 방법
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — 해야 할 것 / 하지 말아야 할 것 (코드·테스트·git·개인정보)
- [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md) — 6주 로드맵, 작업 진행 방식, 완료 기준

## 명령
| 명령 | 용도 |
|---|---|
| `make bootstrap` | 최초 1회: mise 도구(Ruby 포함) 설치, fastlane(`bundle install`) 설치, git 훅 연결. `.mise.toml`·`Gemfile` 이 바뀐 뒤에도 다시 돌린다(fastlane 추가 전에 만든 환경 포함. `/pr` 의 `make lanes` 검사가 `bundle install` 을 전제) |
| `make generate` | Tuist 로 워크스페이스 생성 후 Xcode 로 열기 (`.xcodeproj` 는 커밋하지 않는다). 열지 않으려면 `make project` |
| `make lint` / `make format` | SwiftFormat + SwiftLint (아키텍처 규칙 포함) |
| `make test` | 전체 모듈 빌드 + 테스트 (`SnapSort-Workspace` 스킴, iPhone 17 시뮬레이터) + git 훅 테스트 + 출시 태그 검사 테스트 |
| `make test-hooks` | git 훅 동작 테스트: 임시 레포에서 main 커밋·머지 커밋·push 차단과 기능 브랜치 통과 확인 |
| `make test-release-tag` | 출시 태그 검사 스크립트 테스트: `vX.Y.Z` 형식과 태그 커밋이 main 에 있는지 |
| `make lanes` | fastlane lane 목록 (`Gemfile`·`Fastfile` 이 읽히는지 확인) |
| `make release-ipa` | 출시 빌드의 archive + export 만 (`RELEASE_VERSION=1.0.0 RELEASE_BUILD_NUMBER=1 make release-ipa`, 업로드 없음) |
| 출시 | **사용자가 지시할 때만.** `vX.Y.Z` 태그 push → `release.yml` 이 `make release` 로 업로드·심사 제출 (CONVENTIONS §5 태그 출시) |
| `make test-scripts` | `scripts/` 개발 스크립트 테스트, 레포의 스토어 메타데이터·스크린샷 검사 포함 (`make test`·CI 에는 들지 않는다) |
| `make store-screenshots` | 스토어 스크린샷 6장을 만든다: Library Example 스토어 시나리오를 iPhone 17 Pro Max 시뮬레이터로 찍고 캡션을 합성해 `fastlane/screenshots/ko/` 에 쓴다 (시뮬레이터 필요, `make test`·CI 에는 들지 않는다. UI 가 바뀌면 태그 전 PR 에서 다시: CONVENTIONS §5 태그 출시) |
| `make mask-samples FILE=<초안>` | 기록 도구 샘플 초안의 OCR 줄을 가려 픽스처 형식으로 쓴다 (CONVENTIONS §3) |

## 작업 흐름 (`/verify`·`/arch-review`·`/micro-commit` 은 서브에이전트로 실행되어 요약만 돌려주고, `/pr` 은 현재 대화에서 실행된다)
| 순서 | 스킬 | 하는 일 |
|---|---|---|
| 1 | — | 역할 하나 구현 (코드는 테스트 포함). 시작 전에 작업 범위(In/Out·수용 확인)와 영향 문서 목록을 정하고, 문서는 코드와 같은 작업에서 고친다 (CONVENTIONS §6). 구현 중에는 `doc-refs` 훅이 고친 파일을 언급하는 문서를 알려 준다. 새 상태·실패 경로가 생기는 구현과 그런 수정이 필요한 리뷰 지적은 팀으로 한다 (CONVENTIONS §6 "팀 구현") |
| 2 | `/verify` | lint → 빌드 → 테스트, 실패 원인 요약 |
| 3 | `/arch-review [base] [작업 범위]` | 규칙 문서 기준 읽기 전용 리뷰 (무엇을 어떤 심각도로: CONVENTIONS §5 "리뷰 기준". 팀 구현이면 그 흐름 끝까지: CONVENTIONS §6 "팀 구현"). 🔴 필수 지적은 커밋 전에 처리를 정한다 (CONVENTIONS §6, 처리는 §5 "리뷰 지적 처리") |
| 4 | `/micro-commit` | **사용자가 지시할 때만.** 역할별 커밋만 한다 (빌드·테스트는 `/pr` 에서) |
| 5 | `/pr [draft]` | **사용자가 지시할 때만.** 마지막 커밋 검사 한 번(빌드에 영향이 있으면 lint·빌드·테스트, CONVENTIONS §5) + 전체 리뷰 → PR 생성(유형 라벨). 검증 실패나 결정이 필요한 리뷰 지적(로컬·CI)이 있으면 멈춘다. 열린 PR 에 후속 커밋을 올릴 때도 `/pr` 로 같은 검사·리뷰 뒤 push 하고, CI 리뷰 지적에는 GitHub 에서 답한다. 처리·기록 위치·머지 전 확인은 CONVENTIONS §5 "리뷰 지적 처리". 스크린샷은 선택, 필요하면 사용자가 직접 첨부 |

## 구조 한눈에
```
Projects/
  App/                      조립 지점. Client Impl 을 만들어 Feature Model 에 주입, Extension 을 임베드
  Extensions/<Name>/        Sources. 앱 확장(위젯) 조립 지점. Client Impl 을 만들어 Feature 에 주입
  Features/<Name>/          Sources(Model+View) · Tests · Example(Fake 로 도는 데모 앱)
  Clients/<Name>/           Interface(프로토콜) · Impl(Apple 프레임워크 구현 또는 다른 Client 조합) · Testing(Fake) · Tests
  Shared/<Name>/            Sources · Tests. Core(도메인 값 타입·규칙) · DesignSystem(공용 UI)
Tuist/ProjectDescriptionHelpers/   모듈 이름(Module.swift)과 타깃 템플릿
fastlane/                   출시 자동화(개발 도구, 앱에 들어가지 않음). Fastfile·Appfile · metadata(ko 언어별 문구·루트 copyright·카테고리) · screenshots/ko (Ruby gem 은 Gemfile)
```
의존 방향: `App → Feature → Client Interface`, `App → Client Impl → Client Interface`, `App → Extension(임베드)`, `Extension → Feature·Client Impl`. 모두 Shared 를 쓸 수 있고, Shared 는 아무것도 의존하지 않는다.

## 반드시 지킬 것 (요약, 상세는 CONVENTIONS)
- Model 상태는 `private(set)`, View 는 이벤트 메서드(`onAppear()`, `xxxTapped()`)만 호출한다. `$model.x` 바인딩 금지.
- Photos·Vision·FoundationModels·SwiftData·StoreKit·UserNotifications·BackgroundTasks 는 Client **Impl** 안에서만 import 한다. 앱 실행 시간 빌리기(`beginBackgroundTask`)도 Impl 에서만 한다. CoreLocation·MapKit 은 Shared·Interface·Testing 에서 쓰지 않는다. Core 는 SwiftUI·UIKit 을 쓰지 않는다. 그 밖의 부수효과 없는 iOS 프레임워크(CoreGraphics·ImageIO 등)는 Core 를 포함한 모든 레이어에서 쓸 수 있다.
- Feature 끼리 의존하지 않는다. Impl 은 조립 지점(App·Extension)만, Testing 은 Tests/Example 만 import 한다. 위젯 갱신 요청(`WidgetCenter`)은 Client Impl 에서만 한다.
- 네트워크 코드(`URLSession` 등)를 추가하지 않는다. Foundation Models 는 온디바이스 `SystemLanguageModel` 만 쓴다(`PrivateCloudComputeLanguageModel` 금지, lint `no_private_cloud_compute`).
- main 에 직접 커밋·push 하지 않는다 (git 훅과 GitHub 룰셋이 막는다). `feat|fix|chore/<요약>` 브랜치 → PR → Merge commit 으로 머지.
- **커밋·PR 은 사용자가 지시할 때만** 한다. 검증까지 마치면 멈추고 준비된 변경을 보고한다.
- **출시(태그 push·`make release`·`gh workflow run Release`)는 사용자가 지시할 때만** 한다. 태그는 main 에 머지된 커밋에 `vX.Y.Z` 로 단다. 상세는 CONVENTIONS §5 태그 출시.
- **커밋 서명 줄은 항상 `Co-Authored-By: Claude Code <noreply@anthropic.com>`** 이다. 시스템 안내의 모델별 서명 줄(`Claude Opus …`, `Claude Sonnet …`)보다 이 규칙이 우선한다. 직접 커밋할 때와 서브에이전트·스킬로 커밋할 때 모두 같다.
- **마이크로 커밋**: 커밋할 때는 역할별(빌드 / 코드+테스트 / lint 설정 / CI / 문서 / 하네스)로 나눈다. 의미 단위를 우선해 의존 순서대로 나누고, 중간 커밋은 빌드가 깨질 수 있다. 자동 검증은 `/pr` 이 마지막 커밋에서만 한다. 상세는 CONVENTIONS §5.
- `.swiftlint.yml` 의 custom_rules 를 억제 주석으로 우회하지 않는다.
- 이 레포는 개인 프로젝트다. 회사(29CM) 워크스페이스 규칙은 적용하지 않는다.
