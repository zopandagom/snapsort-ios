#!/bin/bash
# PreToolUse(Bash): main 브랜치에 직접 커밋하거나 main 으로 push 하는 명령을 막는다.
# 무료 플랜 비공개 레포라 GitHub 브랜치 보호를 쓸 수 없어서 하네스에서 대신 막는다.
# jq 가 없으면 cmd 가 비어 모든 명령이 통과하므로(fail-open) 막는다.
command -v jq >/dev/null || { echo "차단됨: main 보호 훅에 jq 가 필요합니다." >&2; exit 2; }
cmd=$(jq -r '.tool_input.command // empty')

git_verb='(^|[;&|(]|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'
is_commit=$(grep -Eq "${git_verb}commit([[:space:]]|$)" <<<"$cmd" && echo 1)
is_push=$(grep -Eq "${git_verb}push([[:space:]]|$)" <<<"$cmd" && echo 1)
[[ -n "$is_commit" || -n "$is_push" ]] || exit 0

block() {
  echo "차단됨: $1 기능 브랜치(feat/…, fix/…, chore/…)에서 작업하고 PR 로 머지하세요. (docs/CONVENTIONS.md)" >&2
  exit 2
}

branch=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null)
[[ "$branch" == "main" && -n "$is_commit" ]] && block "main 브랜치에 직접 커밋할 수 없습니다."
[[ "$branch" == "main" && -n "$is_push" ]] && block "main 브랜치에서 push 할 수 없습니다."
# 같은 명령 안에서 main 으로 전환한 뒤 커밋하는 경우 (실행 전 브랜치만 보면 놓친다)
[[ -n "$is_commit" ]] && grep -Eq "${git_verb}(switch|checkout)[^;&|]*[[:space:]]main([[:space:];&|]|$)" <<<"$cmd" &&
  block "main 으로 전환한 뒤 커밋할 수 없습니다."
# push 인자만 검사한다. 같은 줄의 gh pr create --base main 같은 다른 명령은 보지 않는다.
push_args=$(grep -Eo "${git_verb}push([[:space:]][^;&|]*)?" <<<"$cmd")
[[ -n "$is_push" ]] && grep -Eq '(^|[[:space:]:+/])main([[:space:]]|$)' <<<"$push_args" && block "main 으로 push 할 수 없습니다."
exit 0
