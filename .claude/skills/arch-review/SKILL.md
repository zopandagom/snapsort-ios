---
name: arch-review
description: SnapSort 변경분을 docs/ARCHITECTURE.md·docs/CONVENTIONS.md 기준으로 읽기 전용 리뷰한다 (단방향 MV, 모듈 경계, Swift 6 동시성, 개인정보, 테스트 누락). 구현을 마치고 /verify 가 통과한 뒤 커밋 전에, 또는 사용자가 "리뷰", "검토"를 요청할 때 사용한다. 인자로 비교 기준(예: main, HEAD~3)을 줄 수 있고, 없으면 커밋되지 않은 변경 + main 이후 커밋 전체를 본다.
argument-hint: "[base-ref]"
context: fork
agent: Explore
---

# arch-review

코드를 작성한 대화와 분리된 **읽기 전용** 리뷰어로 실행된다. 작성 의도가 아니라 규칙 문서와 코드만 보고 판단한다. 파일을 수정하지 않는다.

## 1. 기준과 변경분 읽기

1. 규칙 문서를 먼저 읽는다: `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CONVENTIONS.md`.
2. 변경분을 모은다. 기준: `$ARGUMENTS` (비어 있으면 `main`).
   ```bash
   git diff --stat <base>...HEAD; git diff <base>...HEAD   # 커밋된 변경
   git diff HEAD; git status --short                      # 아직 커밋되지 않은 변경 (새 파일은 직접 Read)
   ```
3. diff 만으로 판단이 안 되면 주변 코드(같은 모듈의 Model·Client·매니페스트)를 읽는다.

## 2. 점검 항목 (우선순위 순)

1. **정확성**: 로직 오류, 누락된 상태 전이(권한 `.limited`·`.denied`, 빈 결과, 실패), 잘못된 비동기 순서.
2. **Swift 6 동시성**: `@MainActor` 밖에서 Model 상태 변경, 비 Sendable 값(`PHAsset`, `UIImage` 등)이 actor 경계를 넘음, `@unchecked Sendable`·`nonisolated(unsafe)` 남용, 무거운 작업이 메인에서 실행.
3. **단방향 MV**: `private(set)` 이 아닌 상태, View 가 부수효과를 직접 실행, 이벤트 메서드 이름이 "무슨 일이 일어났는가" 형식이 아님, Model 이 다른 Model 을 참조.
4. **모듈 경계**: 의존 규칙 표 위반, Interface 에 Apple 프레임워크 타입 노출(`CLLocationCoordinate2D` 포함), 매니페스트에서 템플릿 우회·빌드 설정 덮어쓰기, MapKit 경계 위반(Feature View 는 `Map` 렌더링만, 지오코딩·지도 앱 열기는 Client Impl).
5. **개인정보**: 네트워크 코드, OCR 텍스트·기프티콘 번호·사진 식별자 로그, 서드파티 SDK(지도·지오코딩 포함), 사진·OCR 텍스트를 사용자 동작 없이 외부로 보내기, deprecated `CLGeocoder` 사용 (허용 예외: MapKit 에 위치 좌표만 넘기기, 사용자가 누를 때 주소를 지도 앱으로 넘기기).
6. **테스트**: 새 public 이벤트 메서드와 Client Impl 순수 로직의 테스트 누락, 실제 보관함·권한에 의존하는 테스트.
7. **문서 정합성**: 구조나 규칙이 바뀌었는데 docs 가 갱신되지 않음.

**보고하지 않는 것**: SwiftFormat·SwiftLint 로 잡히는 스타일(CI 가 담당), 취향 차이, 변경분 밖의 기존 코드 (심각한 버그면 "범위 밖" 으로 한 줄만).

## 3. 보고 형식

확신이 있는 것만 보고한다. 추측이면 "확인 필요"로 표시한다.

```
## 리뷰 결과: <base>...HEAD (+ 미커밋 N개 파일)

| # | 심각도 | 위치 | 문제 | 규칙 | 수정 방향 |
|---|---|---|---|---|---|
| 1 | 🔴 필수 | Projects/…/LibraryModel.swift:42 | … | ARCHITECTURE 단방향 규칙 #4 | … |
| 2 | 🟡 권장 | … | … | CONVENTIONS §3 | … |

요약: 필수 N · 권장 N
```

- 🔴 필수: 버그, 동시성 오류, 규칙 위반, 개인정보 위반. 커밋 전에 고쳐야 한다.
- 🟡 권장: 테스트 보강, 이름, 문서 갱신.
- 문제가 없으면 `리뷰 결과: 문제 없음 (검토 범위: …)` 한 줄.
