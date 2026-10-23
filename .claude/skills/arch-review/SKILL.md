---
name: arch-review
description: SnapSort 변경분을 docs/ARCHITECTURE.md·docs/CONVENTIONS.md 기준으로 읽기 전용 리뷰한다 (단방향 MV, 모듈 경계, Swift 6 동시성, 개인정보, 테스트 누락, 문서 정합성, 하네스). 구현을 마치고 /verify 가 통과한 뒤 커밋 전에, 또는 사용자가 "리뷰", "검토"를 요청할 때 사용한다. 인자로 비교 기준(예: origin/main, HEAD~3)과 그 뒤에 작업 범위(In/Out·위협 모델)를 줄 수 있고, 비교 기준이 없으면 커밋되지 않은 변경 + origin/main 이후 커밋 전체를 본다.
argument-hint: "[base-ref] [작업 범위]"
context: fork
agent: Explore
model: sonnet
---

# arch-review

코드를 작성한 대화와 분리된 **읽기 전용** 리뷰어로 실행된다. 작성 의도가 아니라 규칙 문서와 코드만 보고 판단한다. 파일을 수정하지 않는다.

## 1. 기준과 변경분 읽기

1. 규칙 문서를 먼저 읽는다: `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CONVENTIONS.md`. 무엇을 어떤 심각도로 지적할지는 CONVENTIONS §5 "리뷰 기준"을 따른다.
2. 변경분을 모은다. 기준: `$ARGUMENTS` 의 첫 단어가 `git rev-parse --verify -q "<첫 단어>^{commit}"` 로 커밋을 가리키면 그것, 아니면(인자가 없거나 범위만 준 경우) `origin/main` (CONVENTIONS §5 "리뷰 기준"의 범위. 최신 origin/main 이 필요하면 부르는 쪽이 `git fetch` 한다. `/pr` 은 §1 에서 한다). 기준으로 쓰지 않은 나머지 인자 전체가 작업 범위다 (CONVENTIONS §5 "리뷰 기준"의 범위. 없으면 Out 이 없다).
   ```bash
   git diff --stat <base>...HEAD; git diff <base>...HEAD   # 커밋된 변경
   git diff HEAD; git status --short                      # 아직 커밋되지 않은 변경 (새 파일은 직접 Read)
   ```
3. diff 만으로 판단이 안 되면 주변 코드(같은 모듈의 Model·Client·매니페스트)를 읽는다.

## 2. 점검 항목 (우선순위 순)

1. **정확성**: 로직 오류, 누락된 상태 전이(권한 `.limited`·`.denied`, 빈 결과, 실패), 잘못된 비동기 순서.
2. **Swift 6 동시성**: `@MainActor` 밖에서 Model 상태 변경, 비 Sendable 값(`PHAsset`, `UIImage` 등)이 actor 경계를 넘음, `@unchecked Sendable`·`nonisolated(unsafe)` 남용, 무거운 작업이 메인에서 실행.
3. **단방향 MV**: `private(set)` 이 아닌 상태, View 가 부수효과를 직접 실행, 이벤트 메서드 이름이 "무슨 일이 일어났는가" 형식이 아님, Model 이 다른 Model 을 참조.
4. **모듈 경계**: 의존 규칙 표 위반, Interface 의 프레임워크 타입 노출, 매니페스트에서 템플릿 우회·빌드 설정 덮어쓰기, MapKit 경계 위반 (허용·예외: ARCHITECTURE §2 "모듈 종류와 타깃", §4 위치·지도 행).
5. **개인정보**: 네트워크 코드, OCR 텍스트·기프티콘 번호·바코드 내용·주소·영수증 가게 이름·금액·사진 식별자·위치 좌표·장소 이름 로그, 서드파티 SDK(지도·지오코딩 포함), 사진·OCR 텍스트를 사용자 동작 없이 외부로 보내기, deprecated `CLGeocoder` 사용 (허용 예외: CONVENTIONS §4).
6. **테스트**: CONVENTIONS §3 이 요구하는 테스트의 누락, 실제 보관함·권한에 의존하는 테스트.
7. **문서 정합성**: CONVENTIONS §5 "리뷰 기준"의 문서 불일치. 이번 변경과 관련된 문서 줄은 문서 범위를 바뀐 타입·함수·동작 이름과 바뀐 규칙의 핵심 문구로 grep 해서 찾는다.
8. **하네스·빌드 설정**(`.claude/**`, `.githooks/**`, `.github/**`, `Makefile`, `Tuist/`, `.mise.toml`): 스크립트 정확성, CONVENTIONS §5 "리뷰 기준"의 fail-open·함께 지킬 수 없는 규칙.

**보고하지 않는 것·범위 밖**: CONVENTIONS §5 "리뷰 기준"을 따른다. 범위 밖(CONVENTIONS §5 "리뷰 기준"의 범위)은 표에 넣지 않고 표 아래에 `범위 밖: 위치 · 문제` 로 한 줄씩 적는다 (🔴 에 해당하면 앞에 🔴, Out 이면 끝에 `(Out)`).

## 3. 보고 형식

확신이 있는 것만 보고한다. 추측이면 "확인 필요"로 표시한다.

```
## 리뷰 결과: <base>...HEAD (+ 미커밋 N개 파일) · 작업 범위: <받은 In/Out 한 줄 또는 없음>

| # | 심각도 | 위치 | 문제 | 규칙 | 수정 방향 |
|---|---|---|---|---|---|
| 1 | 🔴 필수 | Projects/…/LibraryModel.swift:42 | … | ARCHITECTURE 단방향 규칙 #4 | … |
| 2 | 🟡 권장 | … | … | CONVENTIONS §3 | … |

범위 밖: Projects/…/Foo.swift:10 · …
요약: 필수 N · 권장 N
```

- 심각도와 "문제" 칸에 적을 것은 CONVENTIONS §5 "리뷰 기준"을 따른다. 처리(보류·기각 등)는 추천하지 않는다 (`/pr` 이 추천하고 사용자가 정한다, CONVENTIONS §5 "리뷰 지적 처리").
- 요약의 N 은 표의 지적만 센다 (범위 밖 줄 제외).
- 표도 범위 밖 줄도 없으면 `리뷰 결과: 문제 없음 (검토 범위: …)` 한 줄. 범위 밖 줄만 있으면 표 대신 `지적 없음` 한 줄과 범위 밖 줄.
