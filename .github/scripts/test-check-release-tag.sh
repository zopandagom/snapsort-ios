#!/bin/bash
# check-release-tag.sh 가 올바른 출시 태그만 통과시키는지 임시 레포에서 확인한다.
# make test-release-tag 가 실행하고, make test(로컬·CI)가 그것을 포함한다.
# 사용: test-check-release-tag.sh [검사 스크립트]   (기본: 이 스크립트 옆의 check-release-tag.sh)
#   version: 1~7 (vX.Y.Z 통과, v1.0·1.0.0·앞자리 0·접미사·네 자리 거절)
#   on-main: 8~14 (main 커밋·조상·머지 뒤 PR 커밋·annotated 태그 통과, 기능 브랜치·머지 전 PR 커밋·얕은 클론·main ref 없음 거절)
# 거절은 문구까지 확인하므로 check-release-tag.sh 의 문구를 바꾸면 여기도 고친다.
set -euo pipefail

# 테스트가 임시 레포로 cd 하므로 절대 경로로 바꿔 둔다.
check="${1:-$(dirname "${BASH_SOURCE[0]}")/check-release-tag.sh}"
check="$(cd "$(dirname "$check")" && pwd)/$(basename "$check")"
[[ -x "$check" ]] || { echo "검사 스크립트를 실행할 수 없습니다: $check" >&2; exit 1; }

# git 훅 안에서 실행돼도 바깥 레포(GIT_DIR 등)와 사용자·시스템 설정이 섞이지 않게 끊는다.
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tag-test GIT_AUTHOR_EMAIL=tag-test@example.invalid
export GIT_COMMITTER_NAME=tag-test GIT_COMMITTER_EMAIL=tag-test@example.invalid

tmp=$(mktemp -d "${TMPDIR:-/tmp}/snapsort-release-tag.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  [[ -z ${3:-} ]] || sed -n '1,5s/^/       /p' <<<"$3"
  failures=$((failures + 1))
}

# expect <이름> <기대 종료(0|1)> <기대 출력(통과면 stdout 전체, 실패면 stderr 에 든 문구)> -- <인자…>
expect() {
  local name="$1" want="$2" text="$3"
  shift 4
  local out err s
  out=$("$check" "$@" 2>"$tmp/err") && s=0 || s=$?
  err=$(<"$tmp/err")
  if ((want == 0)); then
    if ((s != 0)); then
      fail "$name" "통과해야 하는데 실패했습니다 (종료 $s)" "$err"
    elif [[ -n "$text" && "$out" != "$text" ]]; then
      fail "$name" "출력이 '$text' 가 아닙니다" "$out"
    else
      ok "$name"
    fi
  else
    if ((s == 0)); then
      fail "$name" "거절해야 하는데 통과했습니다" "$out"
    elif ! grep -qF -- "$text" <<<"$err"; then
      fail "$name" "거절 문구 '$text' 가 없습니다 (종료 $s)" "$err"
    else
      ok "$name"
    fi
  fi
}

# --- version ---
format='출시 태그는 vX.Y.Z 형식이어야 합니다'
expect "1. v1.2.3 통과" 0 "1.2.3" -- version v1.2.3
expect "2. v10.0.0 통과" 0 "10.0.0" -- version v10.0.0
expect "3. v1.0 거절" 1 "$format: v1.0" -- version v1.0
expect "4. 1.0.0 거절" 1 "$format: 1.0.0" -- version 1.0.0
expect "5. v01.0.0 거절" 1 "$format" -- version v01.0.0
expect "6. v1.0.0-rc.1 거절" 1 "$format" -- version v1.0.0-rc.1
expect "7. v1.0.0.1 거절" 1 "$format" -- version v1.0.0.1

# --- on-main ---
# 원격(bare)에 main 과 기능 브랜치를 만들고, 작업 레포는 GitHub Actions 처럼 원격에서 받은 origin/main 으로 판정한다.
remote="$tmp/remote.git"
work="$tmp/work"
git init -q --bare -b main "$remote"
git init -q -b main "$work"
cd "$work"
git config commit.gpgsign false
git config tag.gpgsign false
git remote add origin "$remote"
commit() { git commit -q --allow-empty -m "$1" && git rev-parse HEAD; }
old=$(commit old)
main_head=$(commit main)
git switch -q -c feat/x
feature=$(commit feature)
git switch -q main
git push -q origin main feat/x
git fetch -q origin

clone="$tmp/clone"
git clone -q --no-local "$remote" "$clone"
cd "$clone"
not_on_main='태그 커밋이 main 에 없습니다'
expect "8. main 끝 커밋 통과" 0 "" -- on-main "$main_head" origin/main
expect "9. main 의 옛 조상 커밋 통과" 0 "" -- on-main "$old" origin/main
expect "10. 기능 브랜치 커밋 거절" 1 "$not_on_main" -- on-main "$feature" origin/main

# 11. 머지 전 PR 브랜치 끝 커밋은 거절, Merge commit 으로 머지한 뒤에는 통과
cd "$work"
git switch -q -c chore/pr main
pr=$(commit pr)
git push -q origin chore/pr
cd "$clone" && git fetch -q origin
expect "11a. 머지 전 PR 커밋 거절" 1 "$not_on_main" -- on-main "$pr" origin/main
cd "$work"
git switch -q main
git merge -q --no-ff -m "Merge chore/pr" chore/pr
git push -q origin main
cd "$clone" && git fetch -q origin
expect "11b. 머지 뒤 PR 커밋 통과" 0 "" -- on-main "$pr" origin/main

# 12. 얕은 클론은 판정할 수 없으므로 거절
shallow="$tmp/shallow"
git clone -q --no-local --depth 1 "$remote" "$shallow"
cd "$shallow"
expect "12. 얕은 클론 거절" 1 "얕은 체크아웃이라" -- on-main "$(git rev-parse HEAD)" origin/main

# 13. main ref 없음
cd "$clone"
expect "13. main ref 없음 거절" 1 "main ref 를 찾을 수 없습니다: origin/nope" -- on-main "$main_head" origin/nope

# 14. main 커밋을 가리키는 annotated 태그 객체 SHA 는 커밋으로 벗겨 통과
git tag -a -m "v1.0.0" v1.0.0 "$main_head"
tag_object=$(git rev-parse v1.0.0)
if [[ "$tag_object" == "$main_head" ]]; then
  fail "14. annotated 태그 통과" "태그 객체 SHA 가 커밋 SHA 와 같습니다(annotated 태그가 아님)"
else
  expect "14. annotated 태그 통과" 0 "" -- on-main "$tag_object" origin/main
fi

# 기능 브랜치 커밋을 가리키는 annotated 태그는 벗겨도 main 에 없으므로 거절
git tag -a -m "v9.9.9" v9.9.9 "$feature"
expect "14b. 기능 브랜치 annotated 태그 거절" 1 "$not_on_main" -- on-main "$(git rev-parse v9.9.9)" origin/main

echo
if ((failures > 0)); then
  echo "출시 태그 검사 테스트 실패 $failures 건"
  exit 1
fi
echo "출시 태그 검사 테스트 모두 통과"
