#!/bin/bash
# git 훅 스크립트(pre-commit·pre-merge-commit·pre-push)가 main 을 막고 기능 브랜치는 통과시키는지 임시 레포에서 확인한다.
# 임시 레포의 core.hooksPath 를 직접 지정하므로 make bootstrap 의 연결은 다루지 않는다.
# make test-hooks 가 실행하고, make test(로컬·CI)가 그것을 포함한다.
# 사용: test-hooks.sh [훅 디렉터리]   (기본: 이 스크립트가 있는 디렉터리)
#   1. main 커밋 차단      2. 기능 브랜치 커밋 허용
#   3. main push 차단      4. 기능 브랜치 push 허용
#   5. main 머지 커밋 차단  6. 기능 브랜치 머지 커밋 허용
# 임시 레포에는 txt 파일만 커밋하므로 pre-commit 의 Swift lint 부분(mise 필요)은 다루지 않는다.
# 차단은 훅 메시지까지 확인하므로 훅의 echo 문구를 바꾸면 여기도 고친다.
set -euo pipefail

hooks_dir=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)

# git 훅 안에서 실행돼도 바깥 레포(GIT_DIR 등)와 사용자·시스템 설정(hooksPath, gpgsign 등)이 섞이지 않게 끊는다.
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/snapsort-hooks.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
remote="$tmp/remote.git"

git init -q -b main "$repo"
git init -q --bare "$remote"
cd "$repo"
git config user.name hook-test
git config user.email hook-test@example.invalid
git config commit.gpgsign false
git config core.hooksPath "$hooks_dir"
git remote add origin "$remote"
# 기준 커밋은 준비 단계라 훅을 거치지 않는다 (main 이므로 훅이 막는다).
echo base > base.txt
git add base.txt
git commit -q -m base --no-verify
base=$(git rev-parse HEAD)

failures=0
ok() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  [[ -z $3 ]] || sed -n '1,5s/^/       /p' <<<"$3"
  failures=$((failures + 1))
}

# 1. main 커밋 차단
head=$(git rev-parse HEAD)
echo main > main.txt
git add main.txt
out=$(git commit -m main 2>&1) && s=0 || s=$?
if ((s == 0)); then
  fail "main 커밋 차단" "커밋이 성공했습니다" "$out"
elif ! grep -qF 'main 브랜치에 직접 커밋할 수 없습니다' <<<"$out"; then
  fail "main 커밋 차단" "훅의 차단 메시지가 없습니다 (종료 $s)" "$out"
elif [[ $(git rev-parse HEAD) != "$head" ]]; then
  fail "main 커밋 차단" "HEAD 가 바뀌었습니다" "$out"
else
  ok "main 커밋 차단"
fi

# 2. 기능 브랜치 커밋 허용
git switch -q -c feat/hook-test
git reset -q
echo feat > feat.txt
git add feat.txt
head=$(git rev-parse HEAD)
out=$(git commit -m feat 2>&1) && s=0 || s=$?
if ((s != 0)); then
  fail "기능 브랜치 커밋 허용" "커밋이 실패했습니다 (종료 $s)" "$out"
elif [[ $(git rev-parse HEAD) == "$head" || $(git show --name-only --format= HEAD) != feat.txt ]]; then
  fail "기능 브랜치 커밋 허용" "feat.txt 커밋이 만들어지지 않았습니다" "$out"
else
  ok "기능 브랜치 커밋 허용"
fi

# 3. main push 차단
out=$(git push -q origin main 2>&1) && s=0 || s=$?
if ((s == 0)); then
  fail "main push 차단" "push 가 성공했습니다" "$out"
elif ! grep -qF 'main 으로 직접 push 할 수 없습니다' <<<"$out"; then
  fail "main push 차단" "훅의 차단 메시지가 없습니다 (종료 $s)" "$out"
elif git -C "$remote" rev-parse -q --verify refs/heads/main >/dev/null; then
  fail "main push 차단" "remote 에 main 이 생겼습니다" "$out"
else
  ok "main push 차단"
fi

# 4. 기능 브랜치 push 허용
out=$(git push -q origin feat/hook-test 2>&1) && s=0 || s=$?
if ((s != 0)); then
  fail "기능 브랜치 push 허용" "push 가 실패했습니다 (종료 $s)" "$out"
elif [[ $(git -C "$remote" rev-parse -q --verify refs/heads/feat/hook-test || true) != $(git rev-parse HEAD) ]]; then
  fail "기능 브랜치 push 허용" "remote 의 브랜치가 로컬 HEAD 와 다릅니다" "$out"
else
  ok "기능 브랜치 push 허용"
fi

# 5. main 머지 커밋 차단
# feat/hook-test 가 main 보다 앞서 있어 기본 merge 는 fast-forward 로 끝나고 훅이 불리지 않으므로 --no-ff 로 머지 커밋을 만든다.
git switch -q main
head=$(git rev-parse HEAD)
out=$(git merge --no-ff --no-edit feat/hook-test 2>&1) && s=0 || s=$?
if ((s == 0)); then
  fail "main 머지 커밋 차단" "머지가 성공했습니다" "$out"
elif ! grep -qF 'main 브랜치에서 머지 커밋을 만들 수 없습니다' <<<"$out"; then
  fail "main 머지 커밋 차단" "훅의 차단 메시지가 없습니다 (종료 $s)" "$out"
elif [[ $(git rev-parse HEAD) != "$head" ]]; then
  fail "main 머지 커밋 차단" "HEAD 가 바뀌었습니다" "$out"
else
  ok "main 머지 커밋 차단"
fi
# 훅이 막으면 머지가 진행 중인 채로 남으므로 되돌린다.
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  git merge --abort
fi

# 6. 기능 브랜치 머지 커밋 허용
# 5 가 실패해 main 이 바뀌었어도 따로 판정되도록 기준 커밋에서 브랜치를 만든다.
git switch -q -c feat/merge-test "$base"
head=$(git rev-parse HEAD)
out=$(git merge --no-ff --no-edit feat/hook-test 2>&1) && s=0 || s=$?
if ((s != 0)); then
  fail "기능 브랜치 머지 커밋 허용" "머지가 실패했습니다 (종료 $s)" "$out"
elif [[ $(git rev-parse -q --verify HEAD^1 || true) != "$head" || $(git rev-parse -q --verify HEAD^2 || true) != $(git rev-parse feat/hook-test) ]]; then
  fail "기능 브랜치 머지 커밋 허용" "feat/hook-test 를 머지한 커밋이 만들어지지 않았습니다" "$out"
else
  ok "기능 브랜치 머지 커밋 허용"
fi

if ((failures > 0)); then
  echo "FAIL 훅 테스트 ${failures}개 실패"
  exit 1
fi
echo "PASS 훅 테스트 6개"
