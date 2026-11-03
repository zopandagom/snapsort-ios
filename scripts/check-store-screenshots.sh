#!/bin/bash
# 스토어 스크린샷 세트를 검사한다: 6장, 이름은 scripts/store-captions.tsv 의 줄기 + .png, 1320×2868, 알파 없음.
# 출시 lane(fastlane/Fastfile)이 업로드 전에, scripts/store-screenshots.sh 가 반영 전·후에 부른다 (docs/CONVENTIONS.md §5).
# 사용: check-store-screenshots.sh <폴더>
#   - 하위 폴더가 있는 폴더(fastlane/screenshots): 이미지가 정확히 ko/<기대 이름> 6개여야 한다(다른 언어 폴더·여분 파일은 실패).
#     deliver 는 overwrite_screenshots 로 로컬에 이미지가 있는 언어의 ASC 스크린샷을 모두 지우므로, 불완전한 세트를 여기서 막는다.
#   - 하위 폴더가 없는 폴더(합성 결과): 그 폴더 안 이미지가 정확히 <기대 이름> 6개여야 한다.
# 의존: bash·find·sips(macOS 기본).
set -uo pipefail

EXPECTED_COUNT=6 # 바꾸면 store-captions.tsv·store-screenshots.sh 화면 표와 함께 바꾼다
WIDTH=1320
HEIGHT=2868
LANGUAGE=ko

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
CAPTIONS="${STORE_CAPTIONS:-$SCRIPTS/store-captions.tsv}" # 테스트가 지어낸 캡션 파일을 넘길 때만 바꾼다

fail() {
  echo "FAIL 스토어 스크린샷: $1 (make store-screenshots 로 다시 만든 뒤 PR 로 커밋)" >&2
  exit 1
}

(($# == 1)) || {
  echo "사용: $0 <폴더>" >&2
  exit 2
}
dir="${1%/}"
[[ -d $dir ]] || fail "폴더가 없습니다: $dir"

# 기대 목록: 캡션 파일의 주석·빈 줄이 아닌 줄의 첫 열.
[[ -f $CAPTIONS ]] || fail "캡션 목록이 없습니다: $CAPTIONS"
expected=()
while IFS=$'\t' read -r stem _ || [[ -n $stem ]]; do
  [[ -z $stem || $stem == \#* ]] && continue
  [[ $stem =~ ^[0-9]{2}-[a-z-]+$ ]] || fail "캡션 목록의 줄기 형식이 틀립니다: $stem"
  expected+=("$stem.png")
done <"$CAPTIONS"
((${#expected[@]} == EXPECTED_COUNT)) || fail "캡션 목록이 ${EXPECTED_COUNT}장이 아닙니다 (${#expected[@]}줄)"
dupes=$(printf '%s\n' "${expected[@]}" | sort | uniq -d)
[[ -z $dupes ]] || fail "캡션 목록에 겹치는 줄기가 있습니다: $dupes"

# 검사 대상 폴더와 그 안에 있어야 할 상대 경로.
if [[ -n $(find "$dir" -mindepth 1 -type d -print -quit) ]]; then
  prefix="$LANGUAGE/"
else
  prefix=""
fi
want=$(printf "%s\n" "${expected[@]}" | sed "s|^|$prefix|" | LC_ALL=C sort)
have=$(cd "$dir" && find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sed 's|^\./||' | LC_ALL=C sort)
if [[ $have != "$want" ]]; then
  missing=$(LC_ALL=C comm -23 <(echo "$want") <(echo "$have") | grep -v '^$' | tr '\n' ' ')
  extra=$(LC_ALL=C comm -13 <(echo "$want") <(echo "$have") | grep -v '^$' | tr '\n' ' ')
  fail "이미지 목록이 다릅니다: $dir${missing:+ 없음: ${missing% }}${extra:+ 여분: ${extra% }}"
fi

for name in "${expected[@]}"; do
  file="$dir/$prefix$name"
  info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$file" 2>&1) || fail "$prefix$name 을 읽지 못했습니다"
  w=$(awk '/pixelWidth:/ { print $2 }' <<<"$info")
  h=$(awk '/pixelHeight:/ { print $2 }' <<<"$info")
  alpha=$(awk '/hasAlpha:/ { print $2 }' <<<"$info")
  [[ $w == "$WIDTH" && $h == "$HEIGHT" ]] || fail "$prefix$name 이 ${WIDTH}x${HEIGHT} 가 아닙니다 (${w}x${h})"
  [[ $alpha == no ]] || fail "$prefix$name 에 알파 채널이 있습니다"
done

echo "OK 스토어 스크린샷 ${EXPECTED_COUNT}장"
