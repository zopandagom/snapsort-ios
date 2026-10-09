#!/bin/bash
# PostToolUse(Edit|Write|MultiEdit): 수정한 파일을 언급하는 문서 줄을 Claude 에게 알려 준다.
# 구현 중에 같이 고칠 문서를 바로 보게 하려는 것이다. 파일 경로·이름으로만 찾으므로
# 같은 동작을 다른 말로 설명한 문장은 작업 시작 전 영향 문서 목록(CLAUDE.md 작업 흐름 1)이 맡는다.
# 같은 세션에서 파일마다 한 번만 알린다. 실패해도 편집 흐름을 막지 않는다.
input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
session=$(jq -r '.session_id // "none"' <<<"$input")
root="$CLAUDE_PROJECT_DIR"
[[ -n "$file" && -n "$root" && "$file" == "$root"/* ]] || exit 0
rel="${file#"$root"/}"
case "$rel" in .git/* | build/* | */Derived/* | *.xcodeproj/* | *.xcworkspace/*) exit 0 ;; esac

seen="${TMPDIR:-/tmp}/snapsort-doc-refs-$session"
grep -qxF "$rel" "$seen" 2>/dev/null && exit 0
echo "$rel" >>"$seen"

# 찾을 말: 경로, 그리고 흔하지 않은 파일 이름 (Swift 는 확장자를 뺀 타입 이름, 스킬은 `/스킬이름`)
name=$(basename "$rel")
terms=("$rel")
case "$name" in
  SKILL.md) terms+=("\`/$(basename "$(dirname "$rel")")") ;;
  README.md | Project.swift | Package.swift) ;;
  *.swift) terms+=("${name%.swift}") ;;
  *) terms+=("$name") ;;
esac

cd "$root" || exit 0
args=()
for term in "${terms[@]}"; do args+=(-e "$term"); done
hits=$(grep -rnF "${args[@]}" docs CLAUDE.md README.md .claude/skills .github 2>/dev/null |
  grep -v "^$rel:" | cut -c1-200 | head -15)
[[ -n "$hits" ]] || exit 0

jq -n --arg ctx "$rel 을(를) 언급하는 문서입니다. 이번 변경과 어긋나면 같은 작업에서 고치세요:
$hits" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
