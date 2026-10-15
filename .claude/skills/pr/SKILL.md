---
name: pr
description: 현재 기능 브랜치로 SnapSort PR 을 만들거나, 이미 열린 PR 에 후속 커밋을 올린다. PR 전에 마지막 커밋 검사(verify-head.sh: 빌드에 영향이 있으면 lint·빌드·테스트)와 /arch-review(origin/main 기준 전체 범위)를 돌리고, 검증이 실패하거나 처리를 정하지 않은 리뷰 지적(로컬·CI)이 있으면 멈춰서 보고한다. 모든 지적의 처리가 정해진 뒤에만 템플릿을 채워 유형 라벨을 달고 PR 을 열고, 열린 PR 이면 push 뒤 CI 지적에 답한다. 사용자가 /pr 을 지시할 때만 사용한다.
argument-hint: "[draft]"
---

# pr

현재 대화에서 실행된다. PR 본문의 "왜"는 이 대화의 맥락과 커밋을 바탕으로 쓴다. 코드리뷰는 서브에이전트 스킬(/arch-review)에 맡긴다.
/micro-commit 은 커밋만 하므로, 브랜치 마지막 커밋 검사(빌드에 영향이 있으면 lint·빌드·테스트)는 여기서 push 직전에 한 번 한다 (§2). 커밋 뒤에 amend·rebase 를 했어도 실제로 올릴 상태를 검사한다. PR 을 연 뒤에는 CI 가 다시 검증한다.
**이미 열린 PR 에 리뷰 반영 등 후속 커밋을 올릴 때도 이 스킬로 push 한다** ("열린 PR 모드"). CI 는 `.claude/**` 만 바뀐 변경에서 lint·test 를 건너뛰고 settings.json 은 검사하지 않으므로, 로컬 검사(§2)를 거치지 않은 push 는 오류를 그대로 올릴 수 있다. 이 스킬은 force push 하지 않는다 (CONVENTIONS §5 "덮어쓰기 push" 행).

인자: `$ARGUMENTS` — `draft` 가 있으면 초안 PR 로 만든다.

## 1. 사전 확인 — 하나라도 어긋나면 멈추고 보고
```bash
git fetch -q --prune origin
git branch --show-current          # main 이면 중단
git status --short                 # 비어 있어야 한다
git log --oneline origin/main..HEAD
gh pr list --head "$(git branch --show-current)" --state open --json number,url   # 현재 브랜치의 열린 PR
```
- **커밋되지 않은 변경이 있으면 중단한다.** 직접 커밋하지 말고 "커밋이 필요합니다 (/micro-commit 지시 필요)"라고 보고한다.
- origin/main 이후 커밋이 없으면 중단한다.
- `gh pr list` 결과에 PR 이 있으면 **열린 PR 모드**(§3·§4 를 건너뛰고 §5 의 "열린 PR 모드"로 간다), `[]` 면 **새 PR 모드**다. `gh pr list` 자체가 실패하면 멈춘다 (실패를 "PR 없음"으로 보면 열린 PR 에 답을 건너뛴다).
- 브랜치가 `.github/workflows/claude-review.yml` 을 바꿨고(`git diff --quiet origin/main...HEAD -- .github/workflows/claude-review.yml` 이 0 이 아님. 세 점 비교라 main 에서만 바뀐 경우는 들지 않는다), 그 파일이 현재 main 과도 다르면(`git diff --quiet origin/main HEAD -- …` 도 0 이 아님) **CI 리뷰 갈음 PR** 이다 (CONVENTIONS §5 "CI 리뷰 갈음 PR" 행). 진행하되 CI 리뷰 결과는 모으지 않고, 본문에 건너뜀 줄을 적는다 (§4).

## 2. 검증과 코드리뷰
1. 열린 PR 모드면 `gh pr view <N> --json headRefOid,isDraft` 로 원격 head 를 로컬 HEAD 와 비교한다 (실패하면 멈춘다).
   - 같으면 올릴 새 커밋이 없다. `git merge-base --is-ancestor <headRefOid> HEAD` 가 0 이면 올릴 새 커밋이 있다.
   - 그 밖이면(원격에만 있는 커밋이 있다) `git log --oneline HEAD..<headRefOid>` 를 보이고 멈춘다. 가져올지 덮어쓸지는 사용자가 정하고 직접 한다.

   그다음 마지막 커밋 검사를 Bash `run_in_background: true`, `timeout: 1200000`(20분)으로 띄운다. 앞에서 기다리는 Bash 는 10분이 한계라 클린 빌드에서 `make lint`·`make test` 가 도중에 끊길 수 있다.
   ```bash
   .claude/skills/pr/verify-head.sh origin/main
   ```
2. 검사가 도는 동안 다음을 한다. 모든 결과가 온 뒤에 다음 단계로 간다.
   - `/arch-review origin/main` → PR 전체 범위 리뷰 (서브에이전트).
   - 열린 PR 모드이고 갈음 PR 이 아니면 아래 "CI 리뷰 결과 모으기".
   - 새 `withKnownIssue`: 다음 두 명령을 각각 파이프 없이 돌린다 (하나라도 종료 코드가 0 이 아니면 멈춘다).
     `git diff -U0 -G 'withKnownIssue' origin/main...HEAD -- Projects`
     `git diff -U0 -G '"knownIssue"' origin/main...HEAD -- Projects`
     첫 출력은 `withKnownIssue` 를 부르는 `+` 줄 하나가 새 항목이다. 예외는 `Projects/Shared/Core/Tests/ClassificationAccuracyTests.swift` 의 샘플 래퍼(`sample.knownIssue` 를 넘기는 호출) 한 곳뿐이고, 그 샘플은 둘째 출력으로 센다. 그 밖의 호출은 이유를 어떻게 넘기든 항목이다. 둘째 출력은 `"knownIssue"` 키가 있는 `+` 줄 하나가 샘플 하나다. 두 출력 모두 `-` 줄에 같은 내용이 있으면 옮기기만 한 것이고, 이유 문자열을 고쳤으면 새 항목이다.
   - 검사 결과: 출력 첫 단어가 PASS·SKIP·FAIL 이고, 종료 코드가 0 이 아니면 FAIL 로 본다. 검사 항목은 `verify-head.sh` 머리 주석(CONVENTIONS §5 의 PR 전 검사 행)이다. 중간 커밋은 검사하지 않는다 (CONVENTIONS §5).
3. 결과를 표 하나로 보여 준다: `# | 출처 | 심각도 | 위치 | 문제(발생 조건·사용자 영향) | 결정 | 추천`.
   - 행: 로컬 `/arch-review` 지적과 범위 밖 줄, 이 대화에서 사용자가 요청한 다른 리뷰의 지적, CI 리뷰 지적, 새 `withKnownIssue`, 이 대화에서 고치기로 정했는데 아직 고친 커밋을 확인하지 않은 지적. 같은 지적(CONVENTIONS §5 "같은 지적")은 한 행으로 합치고 출처를 모두 적는다.
   - 심각도는 CONVENTIONS §5 "리뷰 지적 처리" 첫 문단대로 판단한다. 리뷰어 표시와 다르면 근거를 함께 적는다.
   - 결정: **결정됨**(이 대화에서 처리를 정했다. 반영은 사용자가 고친 커밋을 확인한 것) 또는 **결정 필요**(새 지적 / 반영 확인 대기 / CONVENTIONS §5 "같은 지적"에서 다시 정하는 경우 / `withKnownIssue` 합의 확인).
   - 추천 (결정 필요 행마다): `고치기(무엇을 어떻게)` / `보류 후보(기준 k: 이유)` / `기각 후보(근거: 파일:줄·실행 결과)` / `범위 밖 후보(후속)` / `확인(후보 커밋 | 합의)`. 반영 확인 대기 행에는 `git log --oneline origin/main..HEAD -- <고칠 파일>` 로 후보 커밋을 보인다. 쓸 수 있는 처리는 CONVENTIONS §5 "리뷰 지적 처리" 표를 따르고, 맞는 것이 없으면 고치기를 추천한다. 발생 조건·사용자 영향을 리뷰만으로 알 수 없으면 코드를 읽고 추천한다.
4. **검사가 FAIL·시간 초과이거나 결정 필요 행이 1건이라도 있으면 PR 을 만들거나 push 하지 않고 멈춘다.** 원인과 표를 보이고 사용자의 결정을 기다린다. 이 스킬 안에서 파일을 수정하지 않는다.
5. 사용자가 결정하면:
   - 고치기: 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다. 다시 /pr 을 실행하면 그 행에 후보 커밋을 보이고, 사용자가 확인하면 반영(그 해시)이다.
   - 보류·기각·범위 밖: CONVENTIONS §5 "리뷰 지적 처리"(쓸 수 있는 지적, 보류할 수 없다, §3 테스트 누락의 보류 기준)에 맞으면 결정됨이다. 맞지 않으면 걸리는 문장을 말하고 다시 묻는다.
   - `withKnownIssue` 합의: 합의했으면 본문에 합의 줄(형식 CONVENTIONS §3)을 두고, 합의 여부만 근거인 지적은 기각(근거: 본문 합의 줄)이다. 합의하지 않았으면 고치기다.
6. 검사가 PASS·SKIP 이고 결정 필요 행이 없으면 새 PR 모드는 "## 3. 라벨", 열린 PR 모드는 "### 열린 PR 모드"로 간다.

### CI 리뷰 결과 모으기
`<N>` 은 §1 의 PR 번호다. 아래 gh 명령의 종료 코드가 0 이 아니면 출력을 쓰지 말고 오류와 함께 멈춘다 (예외: `gh pr checks` 의 `no checks reported` 는 체크 없음, 1 의 표에서 빈 출력과 같다).
1. 원격 head 의 `review` 잡(`.github/workflows/claude-review.yml`) 상태를 본다. 여러 번 돌았으면 하나라도 대기 중이면 `pending`, 아니면 가장 늦게 시작한 실행이다 (대기열의 실행은 `startedAt` 이 비어 정렬로는 고를 수 없다).
   ```bash
   gh pr checks <N> --json name,bucket,startedAt --jq '[.[] | select(.name == "review")] | if length == 0 then empty elif any(.[]; .bucket == "pending") then "pending" else (sort_by(.startedAt) | last | "\(.bucket) \(.startedAt)") end'
   ```
   | 결과 | 할 일 |
   |---|---|
   | `pass` | 2·3 으로 CI 지적을 모은다. 요약이 없으면 아래 "그 밖"과 같다 |
   | `pending` | 올릴 새 커밋이 있으면 CI 지적 없이 진행한다 (push 뒤 새 head 가 리뷰된다). 없으면 기다릴지 묻고, 기다리면 아래 루프를 Bash `run_in_background: true` 로 띄운 뒤 다시 판정한다 |
   | 그 밖 (`fail`·`cancel`·`skipping`, 빈 출력·체크 없음) | 올릴 새 커밋이 있으면 알리고 CI 지적 없이 진행한다. 없으면 상태를 보이고 Actions 에서 다시 돌릴지 이대로 진행할지 묻는다 (초안이면 `skipping` 이 정상이다) |
   ```bash
   while gh pr checks <N> --json name,bucket --jq '.[] | select(.name == "review") | .bucket' | grep -qx pending; do sleep 30; done
   ```
2. 인라인 지적: `claude[bot]` 이 1 의 `startedAt` 뒤에 단 스레드 첫 글(`in_reply_to_id` 가 null).
   ```bash
   gh api --paginate 'repos/{owner}/{repo}/pulls/<N>/comments' --jq '.[] | {id, in_reply_to_id, user: .user.login, path, line, created_at, html_url, body}'
   ```
3. 요약: `claude[bot]` 이 1 의 `startedAt` 뒤에 단 가장 늦은 `## Claude 리뷰` 코멘트. 그 "지적 사항" 표에서 인라인 지적이 없는 행과 `범위 밖:` 줄이 요약-only 지적이다.
   ```bash
   gh api --paginate 'repos/{owner}/{repo}/issues/<N>/comments' --jq '.[] | {id, user: .user.login, created_at, html_url, body}'
   ```

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
  - **검증 · 리뷰**: `verify-head.sh` 결과(PASS 와 검사 항목, 또는 SKIP) 한 줄, 그 아래 다음 줄들.
    - 처리 줄: CI 가 아닌 리뷰(로컬 `/arch-review`, 요청 리뷰) 지적마다 `<지적 요약>: <기록 형식>` (CONVENTIONS §5 "리뷰 지적 처리"). 반영의 커밋은 이 대화에서 사용자가 확인한 해시다. 대화에 기록이 없으면(새 세션 등) 커밋 diff 로 추측해 채우지 말고 생략한다.
    - 합의 줄: 새 `withKnownIssue` 마다(정확도 샘플은 샘플마다) (형식 CONVENTIONS §3).
    - CI 리뷰 갈음 PR 이면 "CI 리뷰는 워크플로 파일 변경으로 건너뜀 (로컬 /arch-review 로 갈음)" 한 줄.
  - **스크린샷 (선택)**: 비워 두고 주석만 남긴다. 사용자가 직접 첨부한다.
- 본문은 임시 파일로 작성해 `--body-file` 로 넘긴다 (본문의 백틱·`$` 가 셸에서 풀리지 않도록).

## 5. push 와 PR 생성
```bash
git push -u origin HEAD
gh pr create --base main --title "<제목>" --body-file <본문 파일> --label <type> [--label <type> …] [--draft]
```
- push 가 실패하면 PR 생성·본문·라벨·답을 하지 않고 멈춘다. non-fast-forward 로 거절되면(같은 이름의 원격 브랜치가 있거나 원격이 바뀜) `git fetch -q origin` 뒤 `git log --oneline HEAD..origin/<브랜치>` 를 보이고 멈춘다. 가져올지 덮어쓸지는 사용자가 정하고 직접 한다.

### 열린 PR 모드
§2-1 에서 올릴 새 커밋이 있었으면 push 하고, 없으면 push 없이 아래 본문·답만 한다. push 가 실패하면 위 push 실패 항목대로 멈춘다.
```bash
git push origin HEAD
```
- 라벨: 라벨에 없는 type 의 커밋이 새로 생겼으면 `gh pr edit <N> --add-label <type>` 만 한다.
- 본문: `gh pr view <N> --json body --jq .body` 로 받아 "검증 · 리뷰" 절만 고친 뒤 `gh pr edit <N> --body-file <파일>` 로 올린다. `verify-head.sh` 결과 줄과 CI 리뷰 건너뜀 줄은 이번 결과로 바꾼다. 처리 줄·합의 줄은 이 대화에서 새로 정한 것만 덧붙이고, 있는 줄은 고치지 않는다 (CONVENTIONS §5 "리뷰 지적 처리"의 기록 문단).
- **답: 이 대화에서 처리를 정했는데 아직 답하지 않은 CI 지적에 답한다.** 내용은 임시 파일에 쓰고(백틱으로 감싼 해시가 셸에서 사라지지 않도록) CONVENTIONS §5 "리뷰 지적 처리"의 기록 형식으로 시작한다.
  - 인라인 지적: 스레드 첫 글 id 에 Reply 한다.
    ```bash
    gh api -X POST 'repos/{owner}/{repo}/pulls/<N>/comments/<id>/replies' -F body=@<파일> --jq .html_url
    ```
  - 요약-only 지적: 한 번 실행에 코멘트 하나만 단다. 지적마다 요약 코멘트 링크와 인용한 행 한 줄, 그 아래 답을 쓴다.
    ```bash
    gh pr comment <N> --body-file <파일>
    ```
  - 이 둘 말고는 새 코멘트를 달지 않는다. 답이나 본문·라벨 편집이 실패하면 나머지를 계속하고 §6 에서 보고한다 (자동으로 다시 시도하지 않는다).

## 6. 보고
- push 나 PR 생성이 실패했으면 그 오류만 보고한다.
- PR 링크, 제목, 라벨, 검증·리뷰 요약(verify-head 결과, 처리·합의 줄) 한 블록. 열린 PR 모드면 push 한 커밋(없으면 "새 커밋 없음"), 단 답(링크), 실패한 답·편집을 적는다.
- 후속: 이 대화에서 정한 후속(CONVENTIONS §5 "리뷰 지적 처리"의 후속 문단) 중 메모리에 없는 것을 프로젝트 메모리에 옮기고 목록으로 보인다. 사용자가 끝났다고 확인한 후속은 메모리에서 지운다.
- 머지 전 확인 (CONVENTIONS §5 "리뷰 지적 처리"): 새 커밋을 push 했거나 PR 을 만들었고 갈음 PR 이 아니면 "CI 리뷰 요약이 올라오면 확인하고, 새 지적이 있으면 /pr 을 다시 실행해 처리한다"고 안내한다 (초안이면 "준비 완료로 바꾼 뒤"). "머지 전 확인 충족"은 이번 실행이 다음을 모두 만족할 때만 적는다: 새 커밋을 push 하지 않았다(갈음 PR 은 push 한 실행도 된다), 원격 head 의 CI 리뷰 요약(갈음 PR 은 이번 로컬 리뷰)을 보고 모든 행이 결정됨이다, 실패한 답·본문·라벨 편집이 없다. 아니면 남은 조건을 적는다.
- UI 변경이 있으면 "스크린샷은 PR 에서 직접 첨부할 수 있습니다" 한 줄.
- 머지는 Merge commit 으로 한다고 덧붙인다. 머지는 하지 않는다.
