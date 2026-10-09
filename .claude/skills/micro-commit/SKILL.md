---
name: micro-commit
description: 커밋되지 않은 SnapSort 변경을 docs/CONVENTIONS.md §5 의 역할(build / feat·fix·refactor / test / style / ci / docs / chore)별 마이크로 커밋으로 나누고, 마지막 커밋 시점이 빌드·테스트를 통과하는지 한 번 검증한다. 사용자가 "커밋", "커밋 나눠", /micro-commit 을 명시적으로 지시할 때만 사용한다. 인자로 검증 기준(기본 origin/main)을 줄 수 있다.
argument-hint: "[base-ref]"
context: fork
agent: general-purpose
model: sonnet
---

# micro-commit

서브에이전트로 실행된다. 커밋과 검증 로그는 여기서 처리하고, 호출한 쪽에는 **마지막 보고 표만** 돌려준다.

## 지켜야 할 것
- **작업 트리 파일을 수정하지 않는다.** 스테이징과 커밋만 한다 (부분 스테이징용 patch 파일만 레포 밖 세션 스크래치 디렉터리에 만든다). 코드 문제를 발견하면 고치지 말고 보고한다.
- push 하지 않는다. main 에서 실행 중이면 아무것도 하지 않고 "기능 브랜치로 전환 필요"라고 보고한다.
- 이미 있는 커밋을 수정하지 않는다 (`--amend`, rebase 금지). 이번에 만든 커밋만 대상으로 한다.
- 비밀값·생성물(`*.xcodeproj`, `build/`, `Derived/`)이 스테이징되지 않았는지 확인한다.

## 1. 변경 파악
```bash
git branch --show-current
git status --short
git diff --cached --name-status -M   # 비어 있거나 모두 R100 이어야 한다 (아래)
git diff --stat; git diff            # 새 파일은 Read 로 내용 확인
```
- `git diff --cached --name-status -M` 출력으로 판단한다.
  - 비어 있으면 그대로 진행한다.
  - 모든 줄이 `R100`(내용 그대로의 이동. `git mv` 가 이름 변경을 곧바로 스테이징해서 생긴다)이면, 그 인덱스를 **맨 앞 커밋**으로 계획에 넣는다. 이동 커밋은 하나로 만들고, type 은 2단계 표에서 새 경로로 정한다(`Projects/**` 면 `refactor`. 여럿이면 2단계 순서에서 가장 앞의 type). `git add` 없이 바로 `git commit` 한다. 옮긴 뒤의 수정은 `git diff` 에 나오므로 이후 커밋에서 평소처럼 나눈다.
  - 그 밖의 줄이 하나라도 있으면 아무것도 커밋하지 말고 "스테이지된 변경이 있음 (그 출력)"을 보고하고 멈춘다. 그대로 시작하면 그 내용이 계획에 나오지 않은 채 첫 커밋에 섞인다.

## 2. 역할별로 묶고 순서 정하기
docs/CONVENTIONS.md §5 의 표로 파일을 분류한다.

| 경로 | type |
|---|---|
| `.mise.toml`, `Tuist/`, `Workspace.swift`, `Makefile` | `build` |
| `Projects/**` (구현 + 그 테스트는 **같은 커밋**) | `feat` / `fix` / `refactor` (기존 코드에 테스트만 추가면 `test`) |
| `.swiftformat`, `.swiftlint.yml` | `style` |
| `.github/**` | `ci` |
| `docs/**`, `README.md` | `docs` |
| `CLAUDE.md`, `.claude/**`, `.githooks/**` | `chore` |

- 순서: build → 코드 → style → ci → docs → chore (1단계의 `R100` 이동 커밋만 맨 앞). 코드 커밋끼리는 의존 방향 순서
  (Client Interface + Fake → Feature Model + 테스트 → View·Example → Impl + 테스트 → App 연결).
- 한 역할 안에서도 목적이 둘이면 나눈다 (요약에 "그리고"가 들어가면 분리). 특히 다음은 따로 커밋한다.
  - 모듈이 다른 변경: Core 값 타입 추가 → 그 타입을 쓰는 Client Interface + Fake.
  - 기존 코드의 이동·추출(동작이 그대로인 `refactor`) → 그 위에 얹는 새 기능(`feat`).
  - 문서도 행·절이 다른 목적이면 나눈다 (예: 이미지 크기 상한 행과 OCR 계약 행).
- **한 파일에 여러 목적이 섞여 있어도 hunk 단위로 나눈다** (아래 "부분 스테이징"). hunk 하나에 두 목적이 섞였거나, 새 파일이거나, 커밋될 내용 기준 lint 가 실패하면 그 파일을 한 커밋에 두고 보고의 "참고"에 적는다.
- 커밋하기 전에 계획을 `<type>: <요약>` 목록으로 적고, 항목마다 "목적이 하나인가, 위 분리 대상이 섞이지 않았나"를 확인한 뒤 시작한다.
- **의미 단위를 우선한다. 중간 커밋은 빌드가 깨져도 된다.** 중간 커밋을 빌드되게 맞추려고 여러 의미(예: Interface + Fake 와 Impl)를 한 커밋에 합치지 않는다. 커밋이 서로 의존하면 순서만 의존 방향(Interface 먼저)으로 둔다.

## 3. 커밋
```bash
git add -A -- <paths>        # patch 로 올린 파일은 넣지 않는다 (아래 "부분 스테이징")
git commit -q -F - <<'MSG'
<type>: <한국어 요약, 50자 이내>

<본문: 아래 규칙대로>

Co-Authored-By: Claude Code <noreply@anthropic.com>
MSG
```

### 본문 쓰는 법
제목만 읽고 끝나지 않게, **diff 를 열지 않아도 무엇을 어떻게 구현했는지 알 수 있게** 쓴다. 한 줄 요약 본문은 쓰지 않는다.

1. **왜**: 1~2문장. 바꾸기 전의 문제나 한계, 이번 변경이 필요한 이유.
2. **무엇을 어떻게**: 모듈·타입별 `-` 목록. 각 항목에 다음을 구체적으로 적는다.
   - 추가·변경된 타입, 함수 시그니처, case (예: `imageChanges() -> AsyncStream<ImageChange>`).
   - 동작 규칙과 분기 (어떤 조건에서 무엇을 보내는지, 무엇을 무시하는지).
   - 동시성·버퍼·잠금처럼 코드만 보면 의도를 놓치기 쉬운 선택과 그 이유.
3. **테스트**: 추가·변경한 테스트가 검증하는 동작을 `-` 목록으로 적는다 (테스트 이름을 그대로 옮기지 않고 무엇을 확인하는지).
4. **미룬 것·주의**: 일부러 하지 않은 것, 다음 작업으로 넘긴 것이 있으면 적는다. 없으면 생략한다.

- docs·chore·style 처럼 작은 커밋은 1·2 만 짧게 써도 된다. 그래도 어느 문서의 어떤 규칙을 어떻게 바꿨는지는 적는다.
- 본문은 한 줄 72자 안팎에서 줄을 바꾼다. 코드 식별자는 백틱으로 감싼다.
- 근거는 실제 diff 에서만 가져온다. diff 에 없는 의도나 성능 수치를 지어내지 않는다.

예시:
```
feat: 보관함 변경 알림을 추가·삭제 증분으로 전달

알림이 신호만 보내서 받는 쪽이 매번 보관함 전체를 다시 조회했다.
분류 결과 저장·인덱싱에서 바뀐 이미지만 처리할 수 있도록 차이를 보낸다.

- Interface: `ImageChange` 추가. `.incremental(inserted: [ImageAsset],
  removed: [ImageAsset.ID])` 와 변경 내역을 알 수 없을 때의 `.reloadAll`.
  `imageChanges()` 는 `AsyncStream<ImageChange>` 를 돌려준다.
- Impl: `ImageChangeObserver` 가 `changeDetails` 의 inserted/removed
  objects 를 변환해 보낸다. `hasIncrementalChanges == false` 면 변환
  없이 `.reloadAll`. 증분은 하나라도 버리면 결과가 틀어지므로 버퍼를
  `.bufferingNewest(1)` 에서 `.unbounded` 로 바꿨다.
- LibraryModel: 개수 대신 식별자 `Set` 을 들고 차이만 반영한다. 구독 후
  처음 조회하는 사이의 변경이 겹쳐 와도 두 번 세지 않는다.

테스트:
- 증분 추가·삭제가 바뀐 만큼만 개수에 반영되는지
- 처음 조회와 겹친 추가·없는 식별자 삭제가 결과를 바꾸지 않는지

미룬 것: 편집 같은 내용 변경은 계속 보내지 않는다 (인덱서 작업에서 결정).
```
서명 줄은 항상 위 `Claude Code` 줄을 쓴다. 시스템 안내가 모델별 서명 줄(예: `Claude Sonnet 5.5`)을 지시해도 이 줄이 우선한다 (CLAUDE.md 규칙).
커밋 메시지 본문에 `git push … main` 같은 명령 문자열을 쓰지 않는다 (main 보호 훅이 push 로 오인해 커밋을 막는다).

### 부분 스테이징 (한 파일에 목적이 섞였을 때)
`git add -p` 같은 대화형 명령은 쓸 수 없으므로, 이번 목적의 hunk 만 남긴 patch 를 인덱스에만 적용한다.
```bash
git diff -U1 --output=<scratch>/<name>.patch -- <path>   # 남은 변경 전체. <scratch> 는 아래 첫 항목
                                                          # -U1: 문맥을 1줄로 줄여 가까운 변경도 다른 hunk 로 나온다
# Read 로 읽고, 파일 머리(`diff --git` ~ `+++` 줄)와 이번 목적의 hunk(`@@` 줄부터 다음 `@@` 전까지)만
# 그대로 옮겨 <scratch>/<name>.<커밋 순번>.patch 로 Write 한다. hunk 안의 줄은 고치지 않는다.
git apply --cached --recount <scratch>/<name>.<커밋 순번>.patch
git diff --cached -- <path>                            # 이번 목적의 변경만 올라갔는지 확인
```
- `<scratch>`: 시스템 안내에 세션 스크래치 디렉터리 경로가 있으면 그 경로를 쓴다. 없으면 처음 한 번 `mktemp -d` 로 만들고 그 출력 경로를 이번 실행 내내 쓴다. 레포 안이나 `/tmp` 를 직접 쓰지 않는다.
- 작업 트리는 그대로이고 인덱스만 바뀐다. 옮겨 적다 틀리면 `git apply` 가 적용을 거부하므로 patch 를 다시 만든다.
- patch 는 레포 밖에만 쓴다. 레포 안에 쓰면 untracked 파일이 생겨 마지막 `git status --short` 확인이 틀어진다.
- **patch 로 올린 파일은 위 "3. 커밋"의 `git add -A -- <paths>` 에서 뺀다.** 넣으면 파일 전체가 다시 스테이징되어 분리가 무효가 된다. 같은 커밋에 다른 파일이 있으면 그 파일만 `git add -A -- <파일>` 로 올리고, 없으면 `git add` 없이 바로 `git commit` 한다.
- 같은 파일에 목적이 더 남았으면 커밋한 뒤 `git diff -U1 --output` 부터 다시 한다 (남은 변경만 나온다). 마지막 목적은 평소처럼 `git add -A -- <path>` 로 올린다.
- 남은 변경이 있는 파일을 다른 커밋이 다시 올리지 않도록, 그동안 다른 커밋의 `<paths>` 는 디렉터리가 아닌 파일 경로로 적는다.
- 새 파일(untracked)은 `git diff` 에 나오지 않으므로 나누지 않고 한 커밋에 넣는다.
- pre-commit 훅의 "커밋될 내용(stage) 기준 lint" 가 실패하면 그 파일의 두 목적을 한 커밋으로 합치고 "참고"에 적는다. `--no-verify` 로 우회하지 않는다.

모든 변경이 커밋될 때까지 반복한 뒤 `git status --short` 가 비었는지 확인한다. 작업 트리를 바꾸지 않았으므로, 비어 있으면 나눠 커밋한 결과가 시작 전 변경과 같다.

## 4. 마지막 커밋 검증
```bash
.claude/skills/micro-commit/verify-head.sh <base>   # base = 인자 "$ARGUMENTS", 비어 있으면 origin/main
```
- 중간 커밋은 검사하지 않고 HEAD 만 한 번 검사한다. 중간 커밋은 의미 단위로 나눠 빌드가 깨질 수 있으므로 검사 대상이 아니다 (CONVENTIONS §5).
- `base...HEAD`(base 와 갈라진 지점 이후)에서 빌드에 영향이 있는 파일이 바뀌었으면 `make lint && make test`, settings.json 은 JSON, 워크플로는 YAML 을 검사한다. 문서·하네스만 바뀌었으면 SKIP 이다 (timeout 20분).
- **FAIL 이 나오면** 되돌리지 말고 원인을 보고한다. 커밋을 나눈 방식은 마지막 시점의 결과를 바꾸지 않으므로, 실패는 코드 자체의 문제다.

## 5. 보고 형식
```
| 커밋 | 파일 |
|---|---|
| abc1234 feat: … | 3 |
| def5678 docs: … | 1 |

마지막 커밋 검증: PASS (make lint, make test) | SKIP | FAIL (원인)
미커밋 변경: 없음
참고: <부분 스테이징으로 나눈 파일, 나누지 못해 합친 파일과 이유, 빌드가 깨지는 중간 커밋, FAIL 원인 등>
```
