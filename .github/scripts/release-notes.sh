#!/bin/bash
# 출시 노트(GitHub Release 본문) 재료 (docs/CONVENTIONS.md §5 태그 출시).
# 부르는 곳: .github/workflows/release.yml notes-summary·notes 잡.
# 테스트: make test-release-tag (.github/scripts/test-release-notes.sh, make test·CI 포함).
# 출력 형식은 테스트가 확인하므로 바꾸면 테스트도 고친다.
#
# 사용:
#   release-notes.sh prs <commit>
#     이전 출시 태그(commit 의 부모에서 닿는 vX.Y.Z 중 가장 높은 버전) 이후 main 에 Merge commit 으로 들어온 PR 을
#     "#번호<TAB>제목" 한 줄씩 오래된 순으로 stdout 에 쓴다. 이전 태그가 없으면 처음부터 본다.
#     PR 은 first-parent 머지 커밋의 제목 "Merge pull request #N from …" 으로 찾고, 제목은 커밋 본문 첫 줄(GitHub 이 PR 제목을 넣는 곳)이다.
#   release-notes.sh previous <commit>
#     위의 이전 출시 태그 이름을 stdout 에 쓴다. 없으면 아무것도 쓰지 않고 0.
#   release-notes.sh body <commit> [요약 파일]
#     Release 본문 markdown 을 stdout 에 쓴다: "## 요약"(요약 파일 내용, 없거나 비면 대체 문구, PR 이 없으면 그렇다는 문구) + "## 포함된 PR"(prs 목록).
#     얕은 체크아웃은 이전 태그·PR 을 놓치므로 실패로 본다.
set -euo pipefail

die() {
  echo "$1" >&2
  exit 1
}

tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

resolve() {
  [[ $(git rev-parse --is-shallow-repository) == false ]] ||
    die "얕은 체크아웃이라 이전 태그·PR 을 찾을 수 없습니다(fetch-depth: 0 필요)."
  git rev-parse --verify -q "$1^{commit}" || die "커밋을 찾을 수 없습니다: $1"
}

# commit 의 부모에서 닿는 출시 태그 중 가장 높은 버전. 같은 커밋에 붙은 태그(같은 버전 다시 달기)는 제외된다.
previous_tag() {
  local commit="$1"
  git rev-parse --verify -q "$commit^" >/dev/null || return 0 # 첫 커밋
  git tag --merged "$commit^" --list 'v*' | { grep -E "$tag_pattern" || true; } |
    sed 's/^v//' | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -n1 | sed 's/^/v/'
}

list_prs() {
  local commit="$1" prev range record subject title
  prev=$(previous_tag "$commit")
  if [[ -n "$prev" ]]; then range="$prev..$commit"; else range="$commit"; fi
  while IFS= read -r -d '' record; do
    subject="${record%%$'\n'*}"
    [[ "$subject" =~ ^Merge\ pull\ request\ \#([0-9]+)\ from\  ]] || continue
    title=$(tail -n +2 <<<"$record" | grep -m1 -v '^[[:space:]]*$' || true)
    printf '#%s\t%s\n' "${BASH_REMATCH[1]}" "${title:-(제목 없음)}"
  done < <(git log -z --reverse --first-parent --merges --format='%s%n%b' "$range")
}

cmd="${1:-}"
case "$cmd" in
  prs)
    (($# == 2)) || die "사용: $0 prs <commit>"
    commit=$(resolve "$2")
    list_prs "$commit"
    ;;
  previous)
    (($# == 2)) || die "사용: $0 previous <commit>"
    commit=$(resolve "$2")
    previous_tag "$commit"
    ;;
  body)
    (($# == 2 || $# == 3)) || die "사용: $0 body <commit> [요약 파일]"
    commit=$(resolve "$2")
    summary_file="${3:-}"
    prev=$(previous_tag "$commit")
    prs=$(list_prs "$commit")

    echo "## 요약"
    if [[ -z "$prs" ]]; then
      echo "이번 버전에 머지된 PR 이 없습니다." # 요약할 것이 없는 것이지 실패가 아니다
    elif [[ -n "$summary_file" && -s "$summary_file" ]] && grep -q '[^[:space:]]' "$summary_file"; then
      cat "$summary_file"
    else
      echo "_요약을 만들지 못했습니다. 아래 PR 목록을 보세요._"
    fi
    echo
    echo "## 포함된 PR"
    if [[ -n "$prev" ]]; then
      echo "$prev 이후 main 에 머지된 PR 입니다."
    else
      echo "첫 출시 태그라 처음부터 main 에 머지된 PR 입니다."
    fi
    echo
    if [[ -n "$prs" ]]; then
      while IFS=$'\t' read -r number title; do
        echo "- $number $title"
      done <<<"$prs"
    else
      echo "- 머지된 PR 이 없습니다."
    fi
    ;;
  *)
    die "사용: $0 prs <commit> | previous <commit> | body <commit> [요약 파일]"
    ;;
esac
