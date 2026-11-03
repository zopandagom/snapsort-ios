#!/bin/bash
# release-notes.sh 가 이전 출시 태그 이후 머지된 PR 만 골라 Release 본문을 만드는지 임시 레포에서 확인한다.
# make test-release-tag 가 실행하고, make test(로컬·CI)가 그것을 포함한다.
# 사용: test-release-notes.sh [노트 스크립트]   (기본: 이 스크립트 옆의 release-notes.sh)
#   previous: 1~4 (첫 태그 전 없음, 같은 커밋 태그를 빼고 가장 높은 버전, 형식 틀린 태그 제외, 첫 커밋)
#   prs: 5~8 (첫 태그는 처음부터, 이전 태그 이후만, PR 아닌 머지·직접 커밋 제외, 제목 없음)
#   body: 9~11 (요약 포함, 요약 없음·빈 요약은 대체 문구, PR 없음은 PR 없음 안내), 12 얕은 클론 거절
# 출력·문구를 비교하므로 release-notes.sh 의 형식을 바꾸면 여기도 고친다.
set -euo pipefail

notes="${1:-$(dirname "${BASH_SOURCE[0]}")/release-notes.sh}"
notes="$(cd "$(dirname "$notes")" && pwd)/$(basename "$notes")"
[[ -x "$notes" ]] || { echo "노트 스크립트를 실행할 수 없습니다: $notes" >&2; exit 1; }

# git 훅 안에서 실행돼도 바깥 레포(GIT_DIR 등)와 사용자·시스템 설정이 섞이지 않게 끊는다.
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=notes-test GIT_AUTHOR_EMAIL=notes-test@example.invalid
export GIT_COMMITTER_NAME=notes-test GIT_COMMITTER_EMAIL=notes-test@example.invalid

tmp=$(mktemp -d "${TMPDIR:-/tmp}/snapsort-release-notes.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  [[ -z ${3:-} ]] || sed -n '1,12s/^/       /p' <<<"$3"
  failures=$((failures + 1))
}

# expect <이름> <기대 stdout 전체> -- <인자…>
expect() {
  local name="$1" want="$2"
  shift 3
  local out s
  out=$("$notes" "$@" 2>"$tmp/err") && s=0 || s=$?
  if ((s != 0)); then
    fail "$name" "통과해야 하는데 실패했습니다 (종료 $s)" "$(<"$tmp/err")"
  elif [[ "$out" != "$want" ]]; then
    fail "$name" "출력이 기대와 다릅니다" "$(printf '기대:\n%s\n실제:\n%s' "$want" "$out")"
  else
    ok "$name"
  fi
}

work="$tmp/work"
git init -q -b main "$work"
cd "$work"
git config commit.gpgsign false
git config tag.gpgsign false
commit() { git commit -q --allow-empty -m "$1"; }
# merge_pr <번호> <브랜치> <PR 제목>: GitHub 의 Merge commit 메시지 형식으로 머지한다.
merge_pr() {
  git switch -q -c "$2" main
  commit "$2 작업"
  git switch -q main
  git merge -q --no-ff -m "Merge pull request #$1 from owner/$2" -m "$3" "$2"
}

commit init
first=$(git rev-parse HEAD)
merge_pr 1 feat/a "기능 A"
git merge -q --no-ff -m "Merge branch 'x'" "$(git switch -q -c x main && commit x && git switch -q main && echo x)"
commit "main 직접 커밋"
merge_pr 2 fix/b "수정 B"
git tag -a -m v1.0.0 v1.0.0
v1=$(git rev-parse HEAD)
git tag v1.0 # 형식이 틀린 태그는 이전 태그로 보지 않는다
merge_pr 3 feat/c "기능 C"
# 제목 줄 없이 머지된 PR
git switch -q -c chore/d main && commit d && git switch -q main
git merge -q --no-ff -m "Merge pull request #4 from owner/chore/d" chore/d
merge_pr 5 feat/e "기능 E"
v2=$(git rev-parse HEAD)
git tag v1.1.0 "$v2"
git tag v1.0.9 "$v1" # 같은 커밋·더 낮은 버전 태그가 섞여도 가장 높은 버전을 고른다
commit "다음 작업"
v3=$(git rev-parse HEAD)

# --- previous ---
expect "1. 첫 태그 전에는 이전 태그 없음" "" -- previous "$v1"
expect "2. 같은 커밋의 v1.1.0 은 빼고 가장 높은 버전 태그" "v1.0.9" -- previous "$v2"
expect "3. 형식 틀린 태그 제외, v1.1.0 이 이전 태그" "v1.1.0" -- previous "$v3"
expect "4. 첫 커밋은 이전 태그 없음" "" -- previous "$first"

# --- prs ---
expect "5. 첫 태그는 처음부터, PR 아닌 머지·직접 커밋 제외" "$(printf '#1\t기능 A\n#2\t수정 B')" -- prs "$v1"
expect "6. 이전 태그 이후 PR 만, 오래된 순, 제목 없음" "$(printf '#3\t기능 C\n#4\t(제목 없음)\n#5\t기능 E')" -- prs "$v2"
expect "7. annotated 태그 이름도 받음" "$(printf '#1\t기능 A\n#2\t수정 B')" -- prs v1.0.0
expect "8. 이전 태그 이후 PR 없음" "" -- prs "$v3"

# --- body ---
printf '이번 버전 개요\n\n- **기능 C**: 설명\n' >"$tmp/summary.md"
expect "9. 요약과 PR 목록" "## 요약
이번 버전 개요

- **기능 C**: 설명

## 포함된 PR
v1.0.9 이후 main 에 머지된 PR 입니다.

- #3 기능 C
- #4 (제목 없음)
- #5 기능 E" -- body "$v2" "$tmp/summary.md"

printf '  \n\n' >"$tmp/blank.md"
fallback="_요약을 만들지 못했습니다. 아래 PR 목록을 보세요._"
expect "10a. 요약 파일 없음은 대체 문구, 첫 태그" "## 요약
$fallback

## 포함된 PR
첫 출시 태그라 처음부터 main 에 머지된 PR 입니다.

- #1 기능 A
- #2 수정 B" -- body "$v1" "$tmp/nope.md"
expect "10b. 빈 요약은 대체 문구" "## 요약
$fallback

## 포함된 PR
첫 출시 태그라 처음부터 main 에 머지된 PR 입니다.

- #1 기능 A
- #2 수정 B" -- body "$v1" "$tmp/blank.md"
expect "11. PR 없음은 대체 문구가 아니라 PR 없음 안내" "## 요약
이번 버전에 머지된 PR 이 없습니다.

## 포함된 PR
v1.1.0 이후 main 에 머지된 PR 입니다.

- 머지된 PR 이 없습니다." -- body "$v3"

# 12. 얕은 클론은 이전 태그·PR 을 놓치므로 거절
shallow="$tmp/shallow"
git clone -q --no-local --depth 1 "file://$work" "$shallow"
cd "$shallow"
if "$notes" prs HEAD >/dev/null 2>"$tmp/err"; then
  fail "12. 얕은 클론 거절" "거절해야 하는데 통과했습니다"
elif ! grep -qF "얕은 체크아웃이라" "$tmp/err"; then
  fail "12. 얕은 클론 거절" "거절 문구가 없습니다" "$(<"$tmp/err")"
else
  ok "12. 얕은 클론 거절"
fi

echo
if ((failures > 0)); then
  echo "출시 노트 스크립트 테스트 실패 $failures 건"
  exit 1
fi
echo "출시 노트 스크립트 테스트 모두 통과"
