#!/bin/bash
# xcresult 를 PR 코멘트용 마크다운으로 요약해 stdout 으로 낸다. CI test 잡이 쓴다.
# 사용: .github/scripts/test-summary.sh build/TestResults.xcresult
# 결과 번들이 없거나 테스트가 하나도 돌지 않았으면 빌드 실패로 본다.
set -uo pipefail

bundle="${1:?xcresult 경로가 필요합니다}"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
max_failures=20
max_text=1000

summary=""
[[ -d "$bundle" ]] && summary=$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null)

if [[ -z "$summary" ]] || [[ $(jq '.totalTestCount // 0' <<<"$summary") -eq 0 ]]; then
  echo "### ❌ 빌드 실패"
  echo "테스트 결과가 없습니다. [실행 로그]($run_url)에서 빌드 오류를 확인하세요."
  exit 0
fi

jq -r --arg run_url "$run_url" --argjson max_failures "$max_failures" --argjson max_text "$max_text" '
  def dur: (.finishTime - .startTime) | floor | "\(. / 60 | floor)분 \(. % 60)초";
  def clip: if length > $max_text then .[:$max_text] + "…" else . end;
  (if .result == "Passed" then "### ✅ 테스트 통과" else "### ❌ 테스트 실패" end),
  "",
  "| 전체 | 통과 | 실패 | 건너뜀 | 소요 |",
  "|---|---|---|---|---|",
  "| \(.totalTestCount) | \(.passedTests) | \(.failedTests) | \(.skippedTests) | \(dur) |",
  "",
  (.devicesAndConfigurations[0].device // empty | "기기: \(.deviceName) (\(.platform) \(.osVersion)) · [실행 로그](\($run_url))"),
  (if (.testFailures | length) > 0 then
    "",
    "<details open><summary>실패한 테스트 (\(.testFailures | length))</summary>",
    "",
    (.testFailures[:$max_failures][] |
      "**\(.targetName)** › `\(.testName)`",
      "```",
      (.failureText // "" | clip),
      "```",
      ""),
    (if (.testFailures | length) > $max_failures then "외 \((.testFailures | length) - $max_failures)건은 실행 로그를 확인하세요." else empty end),
    "</details>"
  else empty end)
' <<<"$summary"
