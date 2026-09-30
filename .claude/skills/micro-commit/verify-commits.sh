#!/bin/bash
# base..HEAD 의 각 커밋을 임시 worktree 에서 체크아웃해 그 시점이 통과하는지 확인한다.
# 사용: verify-commits.sh [base]   (기본: origin/main)
#   - 빌드에 영향을 주는 커밋: make lint && make test
#   - .claude/settings.json 변경: JSON 문법
#   - .github/workflows 변경: YAML 문법
#   - 그 외(문서 등): SKIP
set -uo pipefail

base="${1:-origin/main}"
root=$(git rev-parse --show-toplevel)
# base 가 없거나 검증할 커밋이 없으면 아무것도 확인하지 않은 채 성공으로 끝나므로 실패로 처리한다.
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "base 를 찾을 수 없습니다: $base (git fetch 필요?)" >&2; exit 1; }
revs=$(git rev-list --reverse "$base"..HEAD)
[[ -n "$revs" ]] || { echo "$base..HEAD 에 검증할 커밋이 없습니다." >&2; exit 1; }
wt=$(mktemp -d "${TMPDIR:-/tmp}/snapsort-verify.XXXXXX")
log="$wt.log"
git -C "$root" worktree add -q --detach "$wt" HEAD || exit 1
trap 'git -C "$root" worktree remove --force "$wt"; rm -f "$log"' EXIT
# cd 가 실패하면 아래 checkout/clean 이 실제 레포에서 실행되므로 반드시 중단한다.
cd "$wt" || exit 1
mise trust -q . >/dev/null 2>&1

build_paths='^(Projects/|Tuist/|Workspace\.swift|Tuist\.swift|Makefile|\.mise\.toml|\.swiftlint\.yml|\.swiftformat)'
failed=0

report() { # status subject [detail]
  printf '%-5s %s\n' "$1" "$2"
  [[ -n "${3:-}" ]] && sed 's/^/      /' <<<"$3"
}

for rev in $revs; do
  git checkout -q "$rev" && git clean -qfdX >/dev/null
  subject=$(git log -1 --format='%h %s' "$rev")
  files=$(git diff-tree --no-commit-id --name-only -r "$rev")
  checks=()

  if grep -Eq "$build_paths" <<<"$files"; then
    if [[ -f Makefile ]]; then
      checks+=("make lint" "make test")
    else
      report SKIP "$subject (Makefile 도입 이전 커밋)"
      continue
    fi
  fi
  grep -q '^\.claude/settings\.json$' <<<"$files" && checks+=("jq empty .claude/settings.json")
  grep -Eq '^\.github/workflows/.*\.ya?ml$' <<<"$files" &&
    checks+=("ruby -ryaml -e 'Dir[\".github/workflows/*.y*ml\"].each { |f| YAML.load_file(f) }'")

  if ((${#checks[@]} == 0)); then
    report SKIP "$subject"
    continue
  fi

  : >"$log"
  ok=1
  for check in "${checks[@]}"; do
    bash -c "$check" >>"$log" 2>&1 || { ok=0; break; }
  done
  if ((ok)); then
    report PASS "$subject"
  else
    report FAIL "$subject" "$(grep -E 'error|✖|failed|Error' "$log" | head -10)"
    failed=1
  fi
done

exit $failed
