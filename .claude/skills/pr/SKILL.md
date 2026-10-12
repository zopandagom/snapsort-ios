---
name: pr
description: 현재 기능 브랜치로 SnapSort PR 을 만들거나, 이미 열린 PR 에 후속 커밋을 올린다. PR 전에 마지막 커밋의 lint·빌드·테스트(verify-head.sh)와 /arch-review(origin/main 기준 전체 범위)를 돌리고, 검증이 실패하거나 결정이 필요한 리뷰 지적(로컬·CI)이 있으면 멈춰서 보고한다. 모든 지적이 결정된 뒤에만 템플릿을 채워 유형 라벨을 달고 PR 을 열고, 열린 PR 이면 push 뒤 CI 지적에 답한다. 사용자가 /pr 을 지시할 때만 사용한다.
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
1. 열린 PR 모드면 먼저 아래 "CI 리뷰 결과 모으기" 1 의 조회를 한 번 한다. 체크가 없거나(빈 출력·`no checks reported`) 조회가 실패하면 검사를 띄우지 않고 멈춘다. `pending` 대기 루프는 검사와 함께 띄워도 된다.
   그다음 마지막 커밋 검사를 Bash `run_in_background: true`, `timeout: 1200000`(20분)으로 띄운다. 앞에서 기다리는 Bash 는 10분이 한계라 클린 빌드에서 `make lint`·`make test` 가 도중에 끊길 수 있다.
   ```bash
   .claude/skills/pr/verify-head.sh origin/main
   ```
2. 검사가 도는 동안 `/arch-review origin/main` 을 실행한다 → PR 전체 범위를 리뷰한다 (서브에이전트). 열린 PR 모드면 그동안 "CI 리뷰 결과 모으기"의 나머지도 한다. 새 `withKnownIssue` 도 찾는다. 종료 코드가 0 이 아니면 멈춘다. 출력에서 `+` 로 시작하고 `withKnownIssue` 를 부르는 줄(주석 제외)이 새 항목이다.
   ```bash
   git diff -U0 -G 'withKnownIssue' origin/main...HEAD -- Projects
   ```
   모든 결과가 온 뒤에 다음 단계로 간다.
   - 검사 결과:
     - `origin/main...HEAD` 에서 빌드에 영향이 있는 파일이 바뀌었으면 `make lint && make test`, settings.json 은 JSON, 워크플로는 YAML 을 검사한다. 문서·하네스만 바뀌었으면 SKIP 이다.
     - 중간 커밋은 검사하지 않는다. 의미 단위로 나눠 빌드가 깨질 수 있다 (CONVENTIONS §5).
     - **FAIL 이거나 시간 초과로 끝나면 PR 을 만들지 않고 멈춘다.** push 도 하지 않는다. 원인과 3 의 리뷰 표를 함께 보여 주고, 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다.
3. 리뷰 결과를 표 하나로 보여 준다. 원문을 읽고 판단하고, 판단이 서지 않으면 원문을 보여 주고 묻는다.
   - 행: 로컬 `/arch-review` 지적, CI 지적(인라인 스레드, 최신 요약 표에만 있는 지적), 새 `withKnownIssue`. 같은 지적은 한 행으로 합치고 출처를 모두 적는다.
   - 열: `# | 출처 | 심각도 | 위치 | 문제(발생 조건·사용자 영향) | 결정 | 추천`. 출처는 `로컬`, `CI 스레드 <첫 글 id>`, `CI 요약`, `withKnownIssue`.
   - 결정 열은 둘 중 하나다.
     - **결정됨(출처)**: 이 대화에서 사용자가 보류·반영 확인·합의로 정했다. CI 지적에 사용자의 결정 답(스레드 Reply, 요약을 인용한 답 코멘트)이 있다. 본문 보류·합의 목록에 있다. 또는 이 중 보류·합의로 정한 것과 확실히 같은 지적이 다시 올라왔다(이전 결정 링크를 보인다. 이전 결정이 반영이면 결정 필요다). 이 대화 밖(PR 본문·GitHub 답)에 기록되지 않은 결정은 새 세션에서 다시 묻는다 (의도된 동작).
     - **결정 필요(사유)**: 새 지적 / 반영했는데 같은 지적이 다시 올라옴 / 사용자 답이 질문·메모뿐 / 반영된 듯(지적 뒤 커밋 해시. `line` 이 null 인 것만으로는 아니다) / 합의 확인(새 `withKnownIssue`, 또는 합의 여부만 근거인 지적. 🔴 포함. 이유 인자·지울 시점 주석이 없는 형식 위반은 합의로 닫지 않고 따로 행을 두어 고치기를 추천한다, CONVENTIONS §3).
     - 고치기는 결정이 아니다. 고친 뒤 다음 실행에서 로컬 지적이 다시 나오면 결정 필요, CI 지적은 "반영된 듯"으로 다시 묻는다.
   - 추천 (결정 필요 행마다): `고치기(무엇을 어떻게)` / `보류 후보(기준 k: 이유)` / `확인(반영 커밋 해시 | 합의)`. 기준과 보류할 수 없는 경우는 CONVENTIONS §5 "리뷰 지적 보류"를 따르고, 맞는 기준이 없으면 고치기를 추천한다. 발생 조건·사용자 영향을 리뷰 결과만으로 알 수 없으면 코드를 읽어 확인한 뒤 추천한다.
4. **결정 필요 행이 1건이라도 있으면 PR 을 만들거나 push 하지 않고 멈춘다.** 로컬 지적이 없어도 CI 지적만으로 멈춘다. 사용자의 결정을 기다리고, 이 스킬 안에서 파일을 수정하지 않는다.
5. 사용자가 결정한 뒤에 다시 진행한다.
   - 고치기: 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다. 커밋 후 /pr 을 다시 실행하면 "## 1. 사전 확인"부터 다시 한다.
   - 보류: CONVENTIONS §5 가 보류할 수 없다고 한 지적이거나 그 기준으로는 보류할 수 없는 지적(§3 테스트 누락을 기준 1·2 로)이면 그 이유를 말하고 다시 결정을 받는다.
   - 합의 확인: 합의하지 않았으면 고치기다.
   - 기록 위치는 CONVENTIONS §5 "리뷰 지적 보류"를 따른다. 로컬 지적과 합의는 본문(새 PR 모드 §4, 열린 PR 모드 §5), CI 지적은 push 뒤 답(§5)이다.
6. 다음 단계로 넘어가는 조건: 검사가 PASS·SKIP 이고, 결정 필요 행이 0건이고, 고치기로 정한 행이 없을 때. 열린 PR 모드에서 `review` bucket 이 `fail`·`cancel` 이면 사용자가 이대로 진행을 택했을 때만 넘어간다 (그 선택은 이 대화에서 같은 PR head(마지막으로 push 한 커밋) 동안 유지된다). 새 PR 모드는 "## 3. 라벨"로, 열린 PR 모드는 "## 5. push 와 PR 생성"의 "### 열린 PR 모드"로 간다.

### CI 리뷰 결과 모으기 (열린 PR 모드)
`<N>` 은 §1 의 PR 번호다. 아래 gh 명령은 파이프 없이 `--jq` 로 필드만 고르므로 종료 코드가 gh 의 결과다. **종료 코드가 0 이 아니면 출력을 쓰지 말고 오류와 함께 멈춘다** (실패해도 오류 JSON 이 출력될 수 있다).
1. 최신 head 의 CI 리뷰가 끝났는지 본다 (§2-1 에서 검사를 띄우기 전에). `review` 는 `.github/workflows/claude-review.yml` 의 잡이다. `bucket` 은 `pass`·`fail`·`pending`·`skipping`·`cancel` 중 하나다 (`gh pr checks --help`). `--json` 을 쓰면 대기 중이어도 종료 코드는 0 이다. 초안으로 연 PR 을 준비 완료로 바꾸면 두 줄이 나올 수 있다. 여러 줄이면 멈추는 쪽이 이기도록 `pending` > `fail`·`cancel` > `pass` > `skipping` 순으로 앞선 값 하나로 판정한다.
   ```bash
   gh pr checks <N> --json name,bucket --jq '.[] | select(.name == "review") | .bucket'
   ```
   | 결과 | 할 일 |
   |---|---|
   | `pass` | 2·3 으로 간다 |
   | `pending` | Bash `run_in_background: true`, `timeout: 1500000` 으로 아래 루프를 띄우고, 끝나면 위 명령으로 한 번 더 판정한다. 그래도 pending 이면 멈추고 보고한다. `--watch` 는 review 밖의 체크까지 기다리므로 쓰지 않는다 |
   | `skipping` | 초안 PR 이라 이 head 에는 CI 리뷰가 없다. 알리고 2·3 으로 간다 (이전 리뷰의 지적과 답은 그대로 처리한다) |
   | `fail`·`cancel` | 2·3 까지 마친 표와 함께 알리고, 다시 돌릴지(Actions 에서 사용자가) 이대로 진행할지 묻는다. 이대로 진행을 택했을 때만 다음 단계로 간다. 이 대화에서 같은 PR head 로 이미 진행을 택했으면 묻지 않는다 (§2-6) |
   | 빈 출력, 또는 종료 1 + `no checks reported` | 체크가 아직 등록되지 않았다 (push 직후). 1~2분 뒤 /pr 을 다시 실행하라고 안내하고 멈춘다 |
   | 그 밖의 종료 코드 ≠ 0 | 오류와 함께 멈춘다 |
   ```bash
   while gh pr checks <N> --json name,bucket --jq '.[] | select(.name == "review") | .bucket' | grep -qx pending; do sleep 30; done
   ```
   조회가 실패해도 루프가 끝나므로, 판정은 반드시 위 명령으로 다시 한다.
2. 인라인 리뷰 코멘트. 한 줄이 코멘트 하나다. `in_reply_to_id` 가 null 이면 스레드 첫 글, 아니면 그 스레드의 Reply 다. 출력이 비면 인라인 코멘트가 없다.
   ```bash
   gh api --paginate 'repos/{owner}/{repo}/pulls/<N>/comments' --jq '.[] | {id, in_reply_to_id, user: .user.login, path, line, original_line, created_at, html_url, body}'
   ```
3. PR 코멘트 (CI 요약과 사용자 답 코멘트).
   ```bash
   gh api --paginate 'repos/{owner}/{repo}/issues/<N>/comments' --jq '.[] | {id, user: .user.login, created_at, html_url, body}'
   ```
   `claude[bot]` 의 `## Claude 리뷰` 중 가장 늦은 것의 "지적 사항" 표에서, 인라인 스레드가 없는 행이 요약-only 지적이다. 사용자가 요약을 인용해 단 코멘트가 그 답이다 (어느 요약을 인용했든 같은 지적이면 답이 있는 것이다. 다만 반영 답은 그 답보다 뒤에 나온 요약에 같은 지적이 다시 나오면 답으로 치지 않고 결정 필요다. 같은 요약에 단 반영 답은 답이다). 그 밖의 봇 코멘트(테스트 결과 등)는 무시한다.
4. 본문의 로컬 보류·합의 줄: `gh pr view <N> --json body --jq .body`

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
  - **검증 · 리뷰**: `verify-head.sh` 결과(PASS 와 검사 항목, 또는 SKIP) 한 줄, `리뷰 보류 N` 한 줄(CONVENTIONS §5 "리뷰 지적 보류") + 아래 목록.
    - 반영: 이 브랜치 작업 중 리뷰(/arch-review 등)에서 나와 이미 고친 지적. 항목마다 한 줄로 "무엇을 어떻게 고쳤는지". 출처는 **이 대화에서 확인된 리뷰 결과**로 한정한다. 대화에 기록이 없으면(새 세션 등) 커밋 diff 로 추측해 채우지 말고 생략한다.
    - 보류: 사용자가 보류한 로컬 `/arch-review` 지적마다 `보류(기준 k: 이유)` (기준 3 이면 후속 작업도, CONVENTIONS §5).
    - 합의: 새 `withKnownIssue` 마다 `합의(withKnownIssue): 이유, 지울 시점`.
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
- PR 본문·라벨은 고치지 않는다. 예외는 둘이다.
  - 라벨에 없는 type 의 커밋이 새로 생겼으면 `gh pr edit <N> --add-label <type>` 만 한다.
  - 본문 "검증 · 리뷰" 절에서 `verify-head.sh` 결과 줄, `리뷰 보류 N` 줄, 반영 줄(이 대화에서 확인된 리뷰 결과만), 로컬 보류 줄, 합의 줄, CI 리뷰 건너뜀 줄만 이번 결과에 맞게 고치거나 추가한다 (형식은 §4). 기존 반영·보류·합의 줄은 지우거나 바꾸지 않는다 (이 대화에 기록이 없어도 이전 세션의 결정이다). 본문은 `gh pr view <N> --json body --jq .body` 로 받아 그 줄만 바꾼 뒤 `gh pr edit <N> --body-file <파일>` 로 올린다.
- push 가 non-fast-forward 로 거절되면(amend·rebase 로 이미 올린 커밋을 바꾼 경우) 멈추고 보고한다. force push 는 사용자가 직접 하거나 허락한 뒤에만 `--force-with-lease` 로 한다. push 가 실패하면 답도 달지 않는다.
- **push 뒤 답: §2 표에서 결정됨인데 GitHub 에 그 결정의 답이 없는 CI 지적에 모두 답한다.** 언제 정했는지는 따지지 않는다. 이전 실행에서 정하고 push 하지 못한 것, 답이 실패한 것, 본문에 보류한 로컬 지적과 같은 CI 지적도 포함된다. 인라인 지적은 스레드마다(다시 올라온 새 스레드 포함) 답이 있어야 하고, 요약-only 지적은 지적마다 답이 하나 있으면 된다.
  - 내용은 임시 파일에 쓴다. 반영은 "반영했습니다 (`커밋`). 무엇을 어떻게", 보류는 `보류(기준 k: 이유)` (기준 3 이면 후속 작업도), 합의는 `합의(withKnownIssue): 이유, 지울 시점`, 다시 올라온 지적은 이전 결정 링크와 그 결정 한 줄로 쓴다. 명령줄 문자열로 넘기면 백틱으로 감싼 해시가 셸 명령 치환으로 사라지므로 파일로 넘긴다.
  - 인라인 지적: 스레드 첫 글(`in_reply_to_id` 가 null) id 에 Reply 한다. `-F` 값이 `@` 로 시작하면 파일 내용을 읽는다 (`gh api --help`).
    ```bash
    gh api -X POST 'repos/{owner}/{repo}/pulls/<N>/comments/<id>/replies' -F body=@<파일> --jq .html_url
    ```
  - 요약-only 지적: push 한 번에 코멘트 하나만 단다. 첫 줄에 요약 코멘트 링크(`html_url`), 그 아래 지적마다 요약 표 행을 인용한 한 줄과 답을 쓴다.
    ```bash
    gh pr comment <N> --body-file <파일>
    ```
  - 이 둘 말고는 새 코멘트를 달지 않는다. 종료 코드가 0 이 아니면 대상과 오류를 적어 두고 나머지를 계속한 뒤 §6 에서 보고한다. 자동으로 다시 시도하지 않는다. 다음 /pr 실행에서 같은 규칙으로 다시 대상이 된다.

## 6. 보고
- PR 링크, 제목, 라벨, 검증·리뷰 요약(verify-head 결과, `리뷰 보류 N`, 반영·보류·합의 항목) 한 블록. 열린 PR 모드면 push 한 커밋, 단 Reply·답 코멘트(링크), 실패한 답을 적는다.
- push 했거나 PR 을 만들었으면 (초안이면 준비 완료로 바꾼 뒤) "CI 리뷰가 끝나면(수 분 뒤) /pr 을 다시 실행해 새 지적에 답한다. 새 커밋이 없어도 된다"고 안내한다.
- UI 변경이 있으면 "스크린샷은 PR 에서 직접 첨부할 수 있습니다" 한 줄.
- 머지는 Merge commit 으로 한다고 덧붙인다. 머지는 하지 않는다.
