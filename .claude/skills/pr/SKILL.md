---
name: pr
description: 현재 기능 브랜치로 SnapSort PR 을 만들거나, 이미 열린 PR 에 후속 커밋을 올린다. PR 전에 마지막 커밋의 lint·빌드·테스트(verify-head.sh)와 /arch-review(origin/main 기준 전체 범위)를 돌리고, 검증 실패나 리뷰 지적이 있으면 멈춰서 보고한다. 지적이 없거나 사용자가 보류를 결정한 뒤에만 템플릿을 채워 유형 라벨을 달고 PR 을 연다. 사용자가 /pr 을 지시할 때만 사용한다.
argument-hint: "[draft]"
---

# pr

현재 대화에서 실행된다. PR 본문의 "왜"는 이 대화의 맥락과 커밋을 바탕으로 쓴다. 코드리뷰는 서브에이전트 스킬(/arch-review)에 맡긴다.
/micro-commit 은 커밋만 하므로, 브랜치 마지막 커밋의 lint·빌드·테스트는 여기서 push 직전에 한 번 검사한다 (§2). 커밋 뒤에 amend·rebase 를 했어도 실제로 올릴 상태를 검사한다. PR 을 연 뒤에는 CI 가 다시 검증한다.
**이미 열린 PR 에 리뷰 반영 등 후속 커밋을 올릴 때도 이 스킬로 push 한다** ("열린 PR 모드"). CI 는 `.claude/**` 만 바뀐 변경에서 lint·test 를 건너뛰고 settings.json 은 검사하지 않으므로, 로컬 검사(§2)를 거치지 않은 push 는 오류를 그대로 올릴 수 있다.

인자: `$ARGUMENTS` — `draft` 가 있으면 초안 PR 로 만든다.

## 1. 사전 확인 — 하나라도 어긋나면 멈추고 보고
```bash
git fetch -q origin
git branch --show-current          # main 이면 중단
git status --short                 # 비어 있어야 한다
git log --oneline origin/main..HEAD
gh pr list --head "$(git branch --show-current)" --state open --json number,url   # 현재 브랜치의 열린 PR
```
- **커밋되지 않은 변경이 있으면 중단한다.** 직접 커밋하지 말고 "커밋이 필요합니다 (/micro-commit 지시 필요)"라고 보고한다.
- origin/main 이후 커밋이 없으면 중단한다.
- `gh pr list` 결과에 PR 이 있으면 **열린 PR 모드**다. §2 는 그대로 하고, §3·§4 를 건너뛰어 §5 의 "열린 PR 모드"로 간다. 결과가 `[]` 면(PR 이 없거나 머지·닫힘) **새 PR 모드**로 새 PR 을 만든다. PR 이 없는 것은 어긋남이 아니므로 멈추지 않는다.
- `gh pr list` 자체가 실패하면(인증 만료·네트워크 오류) 멈추고 보고한다. 실패를 "PR 없음"으로 보면 열린 PR 이 있어도 새 PR 모드로 가서 Reply 등을 건너뛴다.
- `git diff --quiet origin/main HEAD -- .github/workflows/claude-review.yml` 로 브랜치의 워크플로 파일이 **현재 main** 과 같은지 확인한다. merge-base 가 아니라 현재 main 과 직접 비교한다. `claude-code-action` 도 현재 main 의 파일과 비교하므로, 세 점(`origin/main...HEAD`, merge-base 기준) 비교로는 브랜치를 만든 뒤 main 에서 바뀐 경우를 놓친다. 다르면 `claude-code-action` 이 리뷰를 건너뛰는데 `review` 체크는 통과로 보인다 (CONVENTIONS §5).
  - 브랜치가 그 파일을 바꾸지 않았는데 다르면(`git diff --name-only origin/main...HEAD` 에 없음 = 브랜치를 만든 뒤 main 에서 바뀜) 중단하고 origin/main 으로 rebase 할 것을 안내한다. 열린 PR 모드면 이미 push 한 커밋이 바뀌므로 rebase 뒤 push 에 `--force-with-lease` 가 필요하고, 사용자 허락을 받아야 한다는 것도 함께 알린다 (§5).
  - 브랜치가 그 파일을 바꿨고 그 밖의 파일도 바뀌었으면 중단하고, 바뀐 파일 목록과 함께 워크플로 커밋을 별도 PR 로 분리할 것을 제안한다. 그 워크플로를 설명하는 문서·하네스 변경도 "그 밖의 파일"이다.
  - 워크플로 파일만 바뀌었으면 진행한다. 본문 "검증 · 리뷰"의 건너뜀 줄은 새 PR 모드는 §4, 열린 PR 모드는 §5 에서 적는다.

## 2. 검증과 코드리뷰
1. 마지막 커밋 검사를 먼저 Bash `run_in_background: true`, `timeout: 1200000`(20분)으로 띄운다. 앞에서 기다리는 Bash 는 10분이 한계라 클린 빌드에서 `make lint`·`make test` 가 도중에 끊길 수 있다.
   ```bash
   .claude/skills/pr/verify-head.sh origin/main
   ```
2. 검사가 도는 동안 `/arch-review origin/main` 을 실행한다 → PR 전체 범위를 리뷰한다 (서브에이전트). 두 결과가 모두 온 뒤에 다음 단계로 간다.
   - 검사 결과:
     - `origin/main...HEAD` 에서 빌드에 영향이 있는 파일이 바뀌었으면 `make lint && make test`, settings.json 은 JSON, 워크플로는 YAML 을 검사한다. 문서·하네스만 바뀌었으면 SKIP 이다.
     - 중간 커밋은 검사하지 않는다. 의미 단위로 나눠 빌드가 깨질 수 있다 (CONVENTIONS §5).
     - **FAIL 이거나 시간 초과로 끝나면 PR 을 만들지 않고 멈춘다.** push 도 하지 않는다. 원인을 보고하고, 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다.
3. **리뷰 지적이 1건이라도 있으면(🔴 필수·🟡 권장 모두) PR 을 만들지 않고 멈춘다.** push 도 하지 않는다.
   - 열린 PR 모드에서는 이미 보류한 🟡 항목은 빼고 센다. 이미 보류한 항목이란 PR 본문 "보류" 목록에 있거나, CI 리뷰 스레드에 보류로 Reply 한 항목이다. `/arch-review` 는 PR 전체를 다시 리뷰하므로 이런 항목이 다시 지적될 수 있다.
   - 리뷰 표를 그대로 보여주고, 항목마다 무엇을 어떻게 고쳐야 하는지 한 줄씩 정리해 보고한다.
   - 사용자의 결정을 기다린다. 이 스킬 안에서 파일을 수정하지 않는다.
4. 사용자가 결정한 뒤에 다시 진행한다.
   - 수정을 지시하면: 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다. 커밋 후 /pr 을 다시 실행하면 "## 1. 사전 확인"부터 다시 한다.
   - 보류를 지시하면: 🔴 필수는 보류할 수 없다. 보류는 다음 곳에 "보류(이유)"로 적는다.
     - 새 PR 모드: §4 본문 "검증 · 리뷰".
     - 열린 PR 모드: 로컬 `/arch-review` 에서 나온 항목은 답할 스레드가 없으므로 PR 본문 "보류" 목록에 줄만 추가한다(§5). CI 리뷰 지적은 §5 처럼 그 스레드에 Reply 한다.
5. 다음 단계로 넘어가는 조건은 하나다: 검사가 PASS·SKIP 이고, 리뷰 지적이 0건이거나 남은 지적이 모두 사용자가 보류한 🟡 권장일 때. 새 PR 모드는 "## 3. 라벨"로, 열린 PR 모드는 "## 5. 열린 PR 모드"로 간다.

## 3. 라벨
커밋 type 에서 결정한다. 라벨은 커밋 type 과 같은 유형 9종뿐이다: `feat` `fix` `refactor` `test` `build` `style` `ci` `docs` `chore`.
```bash
git log --format=%s origin/main..HEAD | sed -E 's/^([a-z]+)(\([^)]*\))?!?:.*/\1/' | sort -u
```
위 9종에 해당하는 것만 모두 단다.

## 4. 제목과 본문
- 제목: `<대표 type>: <한국어 요약>`. 대표 type 은 PR 의 주 목적이다 (보통 feat/fix > refactor > 나머지). 50자 이내.
- 본문: `.github/pull_request_template.md` 의 섹션을 그대로 채운다.
  - **무엇을 / 왜**: 한두 문장.
  - **변경 사항**: 사용자 관점의 변화 위주로 3~6줄.
  - **검증 · 리뷰**: `verify-head.sh` 결과(PASS 와 검사 항목, 또는 SKIP) 한 줄, `/arch-review 필수 0 · 권장 N` 한 줄 + 아래 항목. N 은 §2 의 `/arch-review origin/main` 결과 그대로다 (= 보류 항목 수). 반영 항목은 N 에 넣지 않는다.
    - 반영: 이 브랜치 작업 중 리뷰(/arch-review 등)에서 나와 이미 고친 지적. 항목마다 한 줄로 "무엇을 어떻게 고쳤는지". 출처는 **이 대화에서 확인된 리뷰 결과**로 한정한다. 대화에 기록이 없으면(새 세션 등) 커밋 diff 로 추측해 채우지 말고 생략한다.
    - 보류: 사용자가 보류하기로 한 항목과 이유.
    - CI 리뷰 건너뜀: §1 에서 워크플로 파일만 바뀐 PR 이면 "CI 리뷰는 워크플로 변경으로 건너뜀 (로컬 /arch-review 로 갈음)" 한 줄.
  - **스크린샷 (선택)**: 비워 두고 주석만 남긴다. 사용자가 직접 첨부한다.
- 본문은 임시 파일로 작성해 `--body-file` 로 넘긴다 (명령줄에 `git push … main` 같은 문자열이 들어가면 main 보호 훅이 오인한다).

## 5. push 와 PR 생성
```bash
git push -u origin HEAD
gh pr create --base main --title "<제목>" --body-file <본문 파일> --label <type> [--label <type> …] [--draft]
```

### 열린 PR 모드
```bash
git push origin HEAD
```
- PR 본문·라벨은 고치지 않는다. 예외는 넷이다. 본문은 `gh pr view --json body` 로 받아 해당 줄만 바꾼 뒤 `gh pr edit --body-file` 로 올리고, 다른 줄은 바꾸지 않는다. 바꿀 줄이나 목록이 본문에 없으면(보류 0건으로 만든 PR, 결과 줄이 생기기 전에 만든 PR) "검증 · 리뷰" 절에 새로 만든다.
  - 라벨에 없는 type 의 커밋이 새로 생겼으면 `gh pr edit --add-label <type>` 만 한다.
  - 본문 "검증 · 리뷰"의 `verify-head.sh` 결과 줄을 이번 §2 결과로 바꾼다 (검사 상태를 옮긴 값이라 최신으로 둔다).
  - 로컬 `/arch-review` 지적을 새로 보류했으면 본문 "보류" 목록에 그 줄을 추가하고, `/arch-review 필수 0 · 권장 N` 줄의 N 도 보류 항목 수에 맞게 바꾼다 (§4).
  - §1 에서 워크플로 파일만 바뀐 PR 이고 본문에 CI 리뷰 건너뜀 줄이 없으면 그 줄을 추가한다 (§4).
- push 가 non-fast-forward 로 거절되면(amend·rebase 로 이미 올린 커밋을 바꾼 경우) 멈추고 보고한다. force push 는 사용자가 직접 하거나 허락한 뒤에만 `--force-with-lease` 로 한다.
- push 한 뒤, 이번 커밋이 대응한 CI 리뷰 지적마다 그 리뷰 코멘트 스레드에 Reply 로 반영(무엇을 어떻게, 커밋 해시)·보류(이유)를 답한다. 새 코멘트(`gh pr comment`)는 달지 않는다.
  ```bash
  gh api -X POST repos/<owner>/<repo>/pulls/<N>/comments/<comment id>/replies -f body=<내용>
  ```
  봇이 PR 대화 탭에 단 일반 코멘트처럼 스레드가 없는 지적은 어떻게 답할지 사용자에게 먼저 묻는다.

## 6. 보고
- PR 링크, 제목, 라벨, 검증·리뷰 요약(verify-head 결과, 필수 0 · 권장 N, 반영 항목, 보류 항목) 한 블록. 열린 PR 모드면 push 한 커밋과 Reply 를 단 스레드를 적는다.
- UI 변경이 있으면 "스크린샷은 PR 에서 직접 첨부할 수 있습니다" 한 줄.
- 머지는 Merge commit 으로 한다고 덧붙인다. 머지는 하지 않는다.
