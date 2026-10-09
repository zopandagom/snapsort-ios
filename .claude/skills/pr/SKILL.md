---
name: pr
description: 현재 기능 브랜치로 SnapSort PR 을 만든다. PR 전에 /arch-review(origin/main 기준 전체 범위)를 돌리고, 리뷰 지적이 있으면 멈춰서 수정 사항을 보고한다. 지적이 없거나 사용자가 보류를 결정한 뒤에만 템플릿을 채워 유형 라벨을 달고 PR 을 연다. 사용자가 /pr 을 지시할 때만 사용한다.
argument-hint: "[draft]"
---

# pr

현재 대화에서 실행된다. PR 본문의 "왜"는 이 대화의 맥락과 커밋을 바탕으로 쓴다. 코드리뷰는 서브에이전트 스킬(/arch-review)에 맡긴다.
빌드·테스트는 돌리지 않는다. /micro-commit 이 마지막 커밋에서 이미 검증했고, PR 을 열면 CI 가 다시 검증한다.

인자: `$ARGUMENTS` — `draft` 가 있으면 초안 PR 로 만든다.

## 1. 사전 확인 — 하나라도 어긋나면 멈추고 보고
```bash
git fetch -q origin
git branch --show-current          # main 이면 중단
git status --short                 # 비어 있어야 한다
git log --oneline origin/main..HEAD
```
- **커밋되지 않은 변경이 있으면 중단한다.** 직접 커밋하지 말고 "커밋이 필요합니다 (/micro-commit 지시 필요)"라고 보고한다.
- origin/main 이후 커밋이 없으면 중단한다.

## 2. 코드리뷰
1. `/arch-review origin/main` 실행 → PR 전체 범위를 리뷰한다.
2. **지적이 1건이라도 있으면(🔴 필수·🟡 권장 모두) PR 을 만들지 않고 멈춘다.** push 도 하지 않는다.
   - 리뷰 표를 그대로 보여주고, 항목마다 무엇을 어떻게 고쳐야 하는지 한 줄씩 정리해 보고한다.
   - 사용자의 결정을 기다린다. 이 스킬 안에서 파일을 수정하지 않는다.
3. 사용자가 결정한 뒤에 다시 진행한다.
   - 수정을 지시하면: 고친 뒤 커밋은 사용자 지시(/micro-commit)를 기다린다. 커밋 후 /pr 을 다시 실행하면 "## 1. 사전 확인"부터 다시 한다.
   - 보류를 지시하면: 그 항목을 본문 "검증 · 리뷰"에 "보류(이유)"로 적고 "## 3. 라벨"로 넘어간다. 🔴 필수는 보류할 수 없다.
4. 지적이 0건이면 바로 "## 3. 라벨"로 넘어간다.

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
  - **검증 · 리뷰**: `/arch-review 필수 0 · 권장 N` 한 줄 + 아래 두 가지. N 은 §2 의 `/arch-review origin/main` 결과 그대로다 (= 보류 항목 수). 반영 항목은 N 에 넣지 않는다.
    - 반영: 이 브랜치 작업 중 리뷰(/arch-review 등)에서 나와 이미 고친 지적. 항목마다 한 줄로 "무엇을 어떻게 고쳤는지". 출처는 **이 대화에서 확인된 리뷰 결과**로 한정한다. 대화에 기록이 없으면(새 세션 등) 커밋 diff 로 추측해 채우지 말고 생략한다.
    - 보류: 사용자가 보류하기로 한 항목과 이유.
  - **스크린샷 (선택)**: 비워 두고 주석만 남긴다. 사용자가 직접 첨부한다.
- 본문은 임시 파일로 작성해 `--body-file` 로 넘긴다 (명령줄에 `git push … main` 같은 문자열이 들어가면 main 보호 훅이 오인한다).

## 5. push 와 PR 생성
```bash
git push -u origin HEAD
gh pr create --base main --title "<제목>" --body-file <본문 파일> --label <type> [--label <type> …] [--draft]
```

## 6. 보고
- PR 링크, 제목, 라벨, 검증·리뷰 요약(필수 0 · 권장 N, 반영 항목, 보류 항목) 한 블록.
- UI 변경이 있으면 "스크린샷은 PR 에서 직접 첨부할 수 있습니다" 한 줄.
- 머지는 Merge commit 으로 한다고 덧붙인다. 머지는 하지 않는다.
