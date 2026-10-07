---
name: micro-commit
description: 커밋되지 않은 SnapSort 변경을 docs/CONVENTIONS.md §5 의 역할(build / feat·fix·refactor / test / style / ci / docs / chore)별 마이크로 커밋으로 나누고, 각 커밋 시점이 빌드·테스트를 통과하는지 임시 worktree 에서 검증한다. 사용자가 "커밋", "커밋 나눠", /micro-commit 을 명시적으로 지시할 때만 사용한다. 인자로 검증 기준(기본 origin/main)을 줄 수 있다.
argument-hint: "[base-ref]"
context: fork
agent: general-purpose
model: sonnet
---

# micro-commit

서브에이전트로 실행된다. 커밋과 검증 로그는 여기서 처리하고, 호출한 쪽에는 **마지막 보고 표만** 돌려준다.

## 지켜야 할 것
- **파일 내용을 수정하지 않는다.** 스테이징과 커밋만 한다. 코드 문제를 발견하면 고치지 말고 보고한다.
- push 하지 않는다. main 에서 실행 중이면 아무것도 하지 않고 "기능 브랜치로 전환 필요"라고 보고한다.
- 이미 있는 커밋을 수정하지 않는다 (`--amend`, rebase 금지). 이번에 만든 커밋만 대상으로 한다.
- 비밀값·생성물(`*.xcodeproj`, `build/`, `Derived/`)이 스테이징되지 않았는지 확인한다.

## 1. 변경 파악
```bash
git branch --show-current
git status --short
git diff --stat; git diff            # 새 파일은 Read 로 내용 확인
```

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

- 순서: build → 코드 → style → ci → docs → chore. 코드 커밋끼리는 의존 방향 순서
  (Client Interface + Fake → Feature Model + 테스트 → View·Example → Impl + 테스트 → App 연결).
- 한 역할 안에서도 목적이 둘이면 나눈다 (요약에 "그리고"가 들어가면 분리).
- 한 파일에 여러 목적이 섞여 있으면 억지로 쪼개지 말고 한 커밋에 두고 보고에 적는다.
- 커밋이 서로 컴파일 의존이 있으면 (예: Feature 가 새 Interface 를 사용) 반드시 Interface 쪽을 먼저 커밋한다.

## 3. 커밋
```bash
git add -A -- <paths>
git commit -q -F - <<'MSG'
<type>: <한국어 요약, 50자 이내>

<무엇을 왜 — 1~3줄>

<시스템 안내(attribution)가 지정한 Co-Authored-By 줄. 안내가 없으면 생략>
MSG
```
서명 줄은 직접 정하지 않고 Claude Code 시스템 안내가 주는 줄을 그대로 쓴다 (모델이 바뀌면 함께 바뀐다).
커밋 메시지 본문에 `git push … main` 같은 명령 문자열을 쓰지 않는다 (main 보호 훅이 push 로 오인해 커밋을 막는다).

모든 변경이 커밋될 때까지 반복한 뒤 `git status --short` 가 비었는지 확인한다.

## 4. 커밋별 검증
```bash
.claude/skills/micro-commit/verify-commits.sh <base>   # base = 인자 "$ARGUMENTS", 비어 있으면 origin/main
```
- 빌드에 영향이 있는 커밋은 `make lint && make test`, settings.json 은 JSON, 워크플로는 YAML 을 검사한다. 커밋당 1분 안팎이 걸린다 (timeout 20분).
- **FAIL 이 나오면**: 원인이 커밋 순서·묶음이면, 이번에 만든 커밋만 `git reset --soft <이번 작업 시작 커밋>` 으로 되돌려 다시 나누고 재검증한다 (최대 2회). 코드 자체의 문제면 되돌리지 말고 보고한다.

## 5. 보고 형식
```
| 결과 | 커밋 | 파일 |
|---|---|---|
| PASS | abc1234 feat: … | 3 |
| SKIP | def5678 docs: … | 1 |

미커밋 변경: 없음
참고: <한 파일에 목적이 섞인 경우, 재분할 여부, FAIL 원인 등>
```
