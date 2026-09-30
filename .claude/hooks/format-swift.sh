#!/bin/bash
# PostToolUse(Edit|Write|MultiEdit): 수정된 Swift 파일에 SwiftFormat 을 적용한다.
# 실패해도 편집 흐름을 막지 않는다. 최종 검사는 make lint 와 CI 가 한다.
file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == *.swift && -f "$file" ]] || exit 0
cd "$CLAUDE_PROJECT_DIR" && mise exec -- swiftformat --quiet "$file" >/dev/null 2>&1
exit 0
