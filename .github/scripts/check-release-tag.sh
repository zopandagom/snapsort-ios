#!/bin/bash
# 출시 태그 검사 (docs/CONVENTIONS.md §5 태그 출시).
# 부르는 곳: .github/workflows/release.yml check 잡, fastlane/Fastfile 의 release_version.
# 테스트: make test-release-tag (.github/scripts/test-check-release-tag.sh, make test·CI 포함).
# 문구는 테스트가 확인하므로 바꾸면 테스트도 고친다.
#
# 사용:
#   check-release-tag.sh version <tag>
#     태그가 vX.Y.Z(각 자리는 앞자리 0 없는 정수)면 v 를 뗀 X.Y.Z 를 stdout 에 쓰고 0.
#     App Store 의 CFBundleShortVersionString 은 점으로 나눈 정수 셋까지라 접미사(-rc.1)·네 자리도 거절한다.
#   check-release-tag.sh on-main <sha> <main-ref>
#     커밋(annotated 태그 객체면 그 커밋)이 main-ref 의 조상이면 0.
#     얕은 체크아웃·main-ref 없음은 판정할 수 없으므로 통과가 아니라 실패로 본다.
set -euo pipefail

die() {
  echo "$1" >&2
  exit 1
}

cmd="${1:-}"
case "$cmd" in
  version)
    (($# == 2)) || die "사용: $0 version <tag>"
    tag="$2"
    if [[ "$tag" =~ ^v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$ ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      die "출시 태그는 vX.Y.Z 형식이어야 합니다: $tag"
    fi
    ;;
  on-main)
    (($# == 3)) || die "사용: $0 on-main <sha> <main-ref>"
    sha="$2"
    main_ref="$3"
    [[ $(git rev-parse --is-shallow-repository) == false ]] ||
      die "얕은 체크아웃이라 태그 커밋이 main 에 있는지 판정할 수 없습니다(fetch-depth: 0 필요)."
    main_commit=$(git rev-parse --verify -q "$main_ref^{commit}") ||
      die "main ref 를 찾을 수 없습니다: $main_ref"
    commit=$(git rev-parse --verify -q "$sha^{commit}") ||
      die "커밋을 찾을 수 없습니다: $sha"
    git merge-base --is-ancestor "$commit" "$main_commit" && s=0 || s=$?
    case "$s" in
      0) echo "태그 커밋 $commit 이 $main_ref 에 있습니다." ;;
      1) die "태그 커밋이 main 에 없습니다(기능 브랜치 커밋에 태그?): $commit" ;;
      *) die "git merge-base 가 실패했습니다(종료 $s): $commit $main_ref" ;;
    esac
    ;;
  *)
    die "사용: $0 version <tag> | on-main <sha> <main-ref>"
    ;;
esac
