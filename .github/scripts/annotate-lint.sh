#!/bin/bash
# SwiftFormat·SwiftLint 의 JSON 결과를 Checks API 로 PR 코드 줄에 어노테이션으로 단다. CI lint 잡이 쓴다.
# 사용: .github/scripts/annotate-lint.sh build/swiftformat.json build/swiftlint.json
# 워크플로 명령(::error)은 단계당 10개까지만 표시되므로, 체크를 직접 만들어 50개씩 나눠 전부 올린다.
# 판정은 lint 단계의 종료 코드가 하고, 이 체크는 표시만 한다 (위반이 있으면 neutral).
# 체크를 만들 수 없으면(dependabot 의 읽기 전용 토큰 등) ::error 로 대신 출력한다.
# 필요한 환경 변수: GH_TOKEN, GITHUB_REPOSITORY, HEAD_SHA
set -uo pipefail

check_name="lint 결과"
batch=50

# 결과 파일이 없거나 깨졌으면(도구가 비정상 종료) 빈 목록으로 읽고, 체크 제목에 그 사실을 표시한다.
# 판정은 그 도구의 lint 단계가 이미 실패로 한다.
missing=()
for report in "$@"; do
  jq -e 'type == "array"' "$report" > /dev/null 2>&1 || missing+=("$(basename "$report")")
done
annotations=$(
  for report in "$@"; do
    jq -c 'if type == "array" then . else [] end' "$report" 2>/dev/null || echo '[]'
  done | jq -sc '
    add | map({
      path: (.file | sub("^/work/"; "")),
      start_line: (.line // 1),
      end_line: (.line // 1),
      annotation_level: "failure",
      title: .rule_id,
      message: .reason
    })'
)
count=$(jq 'length' <<<"$annotations")

# 로그에도 전체 목록을 남긴다.
jq -r '.[] | "\(.path):\(.start_line): \(.title) \(.message)"' <<<"$annotations"

if [[ ${#missing[@]} -gt 0 ]]; then
  title="결과 파일 없음: ${missing[*]} — 실행 로그 확인 (위반 ${count}건 표시)"
  conclusion=neutral
elif [[ $count -eq 0 ]]; then
  title="위반 없음"
  conclusion=success
else
  title="위반 ${count}건 (판정은 CI / lint)"
  conclusion=neutral
fi
summary="SwiftFormat·SwiftLint 위반을 코드 줄에 표시합니다. diff 밖의 줄은 이 체크의 Annotations 에만 나옵니다."

output() { # $1 = 시작 인덱스
  jq -c --arg title "$title" --arg summary "$summary" --argjson from "$1" --argjson size "$batch" \
    '{title: $title, summary: $summary, annotations: .[$from:$from + $size]}' <<<"$annotations"
}

check_id=$(
  jq -n --arg name "$check_name" --arg sha "$HEAD_SHA" --arg conclusion "$conclusion" --argjson output "$(output 0)" \
    '{name: $name, head_sha: $sha, status: "completed", conclusion: $conclusion, output: $output}' \
    | gh api "repos/$GITHUB_REPOSITORY/check-runs" --input - --jq '.id' 2>/dev/null
)

if [[ -z $check_id ]]; then
  echo "체크를 만들지 못해 워크플로 명령으로 대신 표시합니다 (단계당 10개까지)." >&2
  jq -r '.[] | "::error file=\(.path),line=\(.start_line),title=\(.title)::\(.message)"' <<<"$annotations"
  exit 0
fi

for ((from = batch; from < count; from += batch)); do
  jq -n --argjson output "$(output "$from")" '{output: $output}' \
    | gh api -X PATCH "repos/$GITHUB_REPOSITORY/check-runs/$check_id" --input - > /dev/null
done
echo "체크 \"$check_name\" 에 어노테이션 ${count}건을 올렸습니다."
