#!/bin/bash
# base..HEAD 에서 바뀐 파일을 보고, 마지막 커밋(HEAD) 시점만 한 번 검사한다.
# 중간 커밋은 검사하지 않는다 (커밋마다 빌드하면 프로젝트가 커질수록 너무 오래 걸린다).
# 사용: verify-head.sh [base]   (기본: origin/main)
#   - 빌드에 영향을 주는 파일: make lint && make test
#   - .claude/settings.json: JSON 문법
#   - .github/workflows: YAML 문법
#   - 그 외(문서 등)만 바뀌었으면: SKIP
# 작업 트리에서 그대로 실행하므로 커밋되지 않은 변경이 없어야 HEAD 를 검사한 것이 된다.
set -uo pipefail

base="${1:-origin/main}"
cd "$(git rev-parse --show-toplevel)" || exit 1
# base 가 없거나 검증할 커밋이 없으면 아무것도 확인하지 않은 채 성공으로 끝나므로 실패로 처리한다.
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "base 를 찾을 수 없습니다: $base (git fetch 필요?)" >&2; exit 1; }
[[ -n $(git rev-list "$base"..HEAD) ]] || { echo "$base..HEAD 에 검증할 커밋이 없습니다." >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "커밋되지 않은 변경이 있어 HEAD 만 검사할 수 없습니다." >&2; exit 1; }

subject=$(git log -1 --format='%h %s' HEAD)
files=$(git diff --name-only "$base"...HEAD)
build_paths='^(Projects/|Tuist/|Workspace\.swift|Tuist\.swift|Makefile|\.mise\.toml|\.swiftlint\.yml|\.swiftformat)'
checks=()
grep -Eq "$build_paths" <<<"$files" && checks+=("make lint" "make test")
grep -q '^\.claude/settings\.json$' <<<"$files" && checks+=("jq empty .claude/settings.json")
grep -Eq '^\.github/workflows/.*\.ya?ml$' <<<"$files" &&
  checks+=("ruby -ryaml -e 'Dir[\".github/workflows/*.y*ml\"].each { |f| YAML.load_file(f) }'")

if ((${#checks[@]} == 0)); then
  echo "SKIP  $subject (검사할 파일 없음)"
  exit 0
fi

log=$(mktemp "${TMPDIR:-/tmp}/snapsort-verify.XXXXXX")
trap 'rm -f "$log"' EXIT
for check in "${checks[@]}"; do
  if ! bash -c "$check" >>"$log" 2>&1; then
    echo "FAIL  $subject ($check)"
    grep -E 'error|✖|failed|Error' "$log" | head -10 | sed 's/^/      /'
    exit 1
  fi
done
echo "PASS  $subject (${checks[*]})"
