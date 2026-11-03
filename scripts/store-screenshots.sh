#!/bin/bash
# 스토어 스크린샷 6장을 만든다: make store-screenshots (docs/CONVENTIONS.md §5). make test·CI 에는 들지 않는다.
# 전용 시뮬레이터(SnapSort Store iPhone 17 Pro Max)에서 Library Example 의 스토어 시나리오(-scenario storeScreenshots)를
# 화면별로 띄워 찍고, scripts/store-captions.tsv 의 캡션을 store-compose.swift 로 합성해 fastlane/screenshots/ko/ 에 쓴다.
# 캡션 글꼴은 DesignSystem 의 나눔스퀘어라운드 EB 파일이다(앱 화면과 같은 글꼴).
# - 데이터는 Example 의 지어낸 값·코드로 그린 그림뿐이다(실제 사진·번호·브랜드 없음).
# - 화면마다 연속 캡처가 정해진 시간 동안 픽셀까지 같고(채널 차 16 이하), 다이내믹 아일랜드·흰 실행 화면이 아닐 때 찍는다
#   (판정은 scripts/store-frame.swift). 시한 안에 멈추지 않으면 실패하고 fastlane/screenshots/ko 는 그대로다.
#   화면별 연속 캡처는 build/store-screenshots/settle/<줄기>/ 에 남는다(실패 진단용).
# - fastlane/screenshots/ko/ 는 마지막 단계에서 폴더째 바꿔치기한다: 어느 단계에서 실패해도 기존 세트나 새 세트 중 하나가 온전히 남는다.
# - 중간 산출물은 build/store-screenshots/(raw 캡처·연속 캡처·비교 도구·합성 결과·빌드 로그·DerivedData). 다른 세션의 make build 와 겹치지 않게 따로 빌드한다.
# - 같은 맥·같은 시뮬레이터 런타임이면 다시 돌려도 눈으로는 같은 결과다(실측 3회: 01·05·06 은 바이트 동일, 02·03 은 렌더 반올림으로
#   색이 최대 1~2 달라 바이트가 다를 수 있고, 04-trip 은 Apple 지도 타일 로딩 차이로 다를 수 있다). 합성은 입력이 같으면 바이트가 같다.
#   그래서 다시 찍은 뒤에는 바이트가 아니라 눈으로 같은지 비교한다.
# 사용: scripts/store-screenshots.sh          촬영
#       scripts/store-screenshots.sh --list   화면 표(<줄기>\t<화면 키>)만 출력 (테스트용)
# 환경 변수: STORE_SCREENSHOT_WAIT_SCALE(정수, 기본 1) — 화면별 시한 배수. 느리거나 바쁜 맥에서 시한을 늘린다(안정 유지 초는 그대로).
set -euo pipefail

# 줄기(파일 이름) → Example 의 -storeScreen 키, 안정 유지 초(같은 장이 이만큼 이어져야 받아들임), 시한 초.
# store-captions.tsv 줄기와 같은 순서여야 한다. trip 은 지도 칸이 비어 있다가 타일이 오는 화면이라 유지를 길게 둔다.
SCREENS=(
  "01-home home 3 60"
  "02-gifticons gifticons 3 60"
  "03-gifticon-detail gifticonDetail 3 60"
  "04-trip trip 6 90"
  "05-search search 3 60"
  "06-cleanup cleanup 3 60"
)

# 화면 표(<줄기>\t<화면 키>). --list 와 캡션 대조가 함께 쓴다(자기 자신을 다시 부르지 않아 실행 위치와 무관하다).
list_screens() {
  for entry in "${SCREENS[@]}"; do
    read -r stem key _ <<<"$entry"
    printf '%s\t%s\n' "$stem" "$key"
  done
}

if [[ ${1:-} == --list ]]; then
  list_screens
  exit 0
fi

fail() {
  echo "FAIL $1" >&2
  exit 1
}

# 0 준비
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in xcrun swift swiftc python3 mise; do
  command -v "$tool" >/dev/null || fail "준비: $tool 이 없습니다"
done
[[ -d SnapSort.xcworkspace ]] || fail "준비: SnapSort.xcworkspace 가 없습니다 (make project 로 먼저 생성)"
WAIT_SCALE="${STORE_SCREENSHOT_WAIT_SCALE:-1}"
[[ $WAIT_SCALE =~ ^[1-9][0-9]*$ ]] || fail "준비: STORE_SCREENSHOT_WAIT_SCALE 은 양의 정수여야 합니다 ($WAIT_SCALE)"
CAPTIONS=scripts/store-captions.tsv
# 캡션 글꼴: 앱과 같은 나눔스퀘어라운드 EB. 없거나 못 읽으면 합성이 FAIL 로 멈춘다(시스템 글꼴로 떨어지지 않는다).
CAPTION_FONT=Projects/Shared/DesignSystem/Resources/Fonts/NanumSquareRoundOTFEB.otf
[[ -r $CAPTION_FONT ]] || fail "준비: 캡션 글꼴 파일이 없습니다 ($CAPTION_FONT)"
caption_stems=$(grep -v -e '^#' -e '^[[:space:]]*$' "$CAPTIONS" | cut -f1) || fail "준비: $CAPTIONS 를 읽지 못했습니다"
[[ $caption_stems == "$(list_screens | cut -f1)" ]] || fail "준비: 캡션 파일과 화면 목록이 다릅니다 ($CAPTIONS, scripts/store-screenshots.sh 의 SCREENS)"

WORK=build/store-screenshots
RAW="$WORK/raw"
OUT="$WORK/out"
DEST=fastlane/screenshots/ko
DEVICE_NAME="SnapSort Store iPhone 17 Pro Max"
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
mkdir -p "$WORK/bin"
FRAME="$WORK/bin/store-frame"
swiftc -O scripts/store-frame.swift -o "$FRAME" >"$WORK/frame-build.log" 2>&1 ||
  fail "준비: 화면 비교 도구를 컴파일하지 못했습니다 ($WORK/frame-build.log)"

# 1 기기: 전용 기기를 찾고, 없으면 지원 런타임 중 가장 높은 iOS 로 만든다(다른 시뮬레이터 상태를 건드리지 않는다).
UDID=$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d.get("isAvailable"):
            print(d["udid"]); sys.exit(0)
' "$DEVICE_NAME") || fail "기기: simctl list devices 를 읽지 못했습니다"
if [[ -z $UDID ]]; then
  RUNTIME=$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
kind = sys.argv[1]
runtimes = [
    r for r in json.load(sys.stdin)["runtimes"]
    if r.get("isAvailable") and r.get("platform") == "iOS"
    and any(t.get("identifier") == kind for t in r.get("supportedDeviceTypes", []))
]
if runtimes:
    best = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
    print(best["identifier"])
' "$DEVICE_TYPE") || fail "기기: simctl list runtimes 를 읽지 못했습니다"
  [[ -n $RUNTIME ]] || fail "기기: iPhone 17 Pro Max 를 지원하는 iOS 시뮬레이터 런타임이 없습니다 (Xcode → Settings → Components)"
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME" 2>&1) || fail "기기: $UDID"
  echo "기기 만듦: $DEVICE_NAME ($RUNTIME)"
fi

cleanup() {
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 2 부팅
state=$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["udid"] == sys.argv[1]:
            print(d["state"])
' "$UDID") || fail "부팅: simctl list devices 를 읽지 못했습니다"
if [[ $state != Booted ]]; then
  out=$(xcrun simctl boot "$UDID" 2>&1) || fail "부팅: $out"
fi
out=$(xcrun simctl bootstatus "$UDID" -b 2>&1) || fail "부팅: $out"

# 3 외관: 라이트, 동작 줄이기(곧 만료 배지 맥박 정지), 상태 막대 9:41·충전 표시 없는 꽉 찬 배터리.
out=$(xcrun simctl ui "$UDID" appearance light 2>&1) || fail "외관: $out"
out=$(xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true 2>&1) ||
  fail "외관: 동작 줄이기 $out"
out=$(xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100 --operatorName '' 2>&1) ||
  fail "외관: $out"

# 4 빌드
echo "빌드: SnapSort-Workspace 스킴의 LibraryFeatureExample (로그 $WORK/build.log)"
if ! mise exec -- xcodebuild build -workspace SnapSort.xcworkspace -scheme SnapSort-Workspace \
  -destination "id=$UDID" -derivedDataPath "$WORK/DerivedData" CODE_SIGNING_ALLOWED=NO 2>&1 |
  tee "$WORK/build.log" | mise exec -- xcbeautify --quiet; then
  grep -m 20 'error:' "$WORK/build.log" >&2 || true
  fail "빌드: $WORK/build.log"
fi
APP="$WORK/DerivedData/Build/Products/Debug-iphonesimulator/LibraryFeatureExample.app"
[[ -d $APP ]] || fail "빌드: 앱이 없습니다 ($APP)"

# 5 설치: 지웠다 깔아 이전 실행의 UserDefaults 가 남지 않게 한다.
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist") || fail "설치: 번들 ID 를 읽지 못했습니다"
xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
out=$(xcrun simctl install "$UDID" "$APP" 2>&1) || fail "설치: $out"

# 6 화면별 촬영: 고정 대기 대신 연속 캡처를 비교해 화면이 멈출 때까지 기다린다.
# 같음(0)이 "안정 유지 초" 이상, 최소 횟수(trip 3, 나머지 2) 이상 이어지면 마지막 장을 받아들인다($SECONDS 가 1초 단위라
# 시간만 보면 바쁜 맥에서 같은 쌍 하나로 받아들일 수 있어 횟수도 본다). 다름(1)·시스템 표시(3)·빈 화면(4)이면 처음부터 다시 센다.
rm -rf "$RAW" "$OUT" "$WORK/settle"
mkdir -p "$RAW"
timings=()
for entry in "${SCREENS[@]}"; do
  read -r stem key hold limit <<<"$entry"
  limit=$((limit * WAIT_SCALE))
  min_same=2
  [[ $key == trip ]] && min_same=3
  settle="$WORK/settle/$stem"
  mkdir -p "$settle"
  echo "촬영: $stem ($key)"
  out=$(SIMCTL_CHILD_TZ=Asia/Seoul xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
    -scenario storeScreenshots -storeScreen "$key" -AppleLanguages '(ko)' -AppleLocale ko_KR 2>&1) ||
    fail "실행 $key: $out"
  start=$SECONDS
  n=0
  prev=""
  prev_at=0
  run_start=""
  same=0
  verdict="(아직 비교 전)"
  while :; do
    cur=$(printf '%s/%02d.png' "$settle" "$n")
    out=$(xcrun simctl io "$UDID" screenshot --type=png "$cur" 2>&1) || fail "캡처 $key: $out"
    cur_at=$SECONDS
    n=$((n + 1))
    if [[ -n $prev ]]; then
      rc=0
      verdict=$("$FRAME" "$prev" "$cur") || rc=$?
      case "$rc:$verdict" in
        "0:같음")
          [[ -n $run_start ]] || run_start=$prev_at
          same=$((same + 1))
          if ((cur_at - run_start >= hold && same >= min_same)); then
            cp "$cur" "$RAW/$stem.png" || fail "캡처 $key: $RAW/$stem.png 로 복사하지 못했습니다"
            timings+=("촬영: $stem $((cur_at - start))초 만에 안정 (캡처 ${n}장)")
            break
          fi
          ;;
        "1:다름:"* | "3:시스템 표시:"* | "4:빈 화면:"*)
          run_start=""
          same=0
          ;;
        *) fail "캡처 $key: $verdict" ;;
      esac
    fi
    prev=$cur
    prev_at=$cur_at
    if ((SECONDS - start > limit)); then
      fail "촬영 $key: ${limit}초 안에 화면이 멈추지 않았습니다 (마지막 판정: $verdict, 캡처 $settle/). 맥이 바쁘면 다른 작업을 멈추거나 STORE_SCREENSHOT_WAIT_SCALE=2 로 다시"
    fi
    sleep 0.5
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

# 7 합성
out=$(swift scripts/store-compose.swift "$CAPTIONS" "$RAW" "$OUT" "$CAPTION_FONT" 2>&1) || fail "합성: $out"

# 8 검사
out=$(scripts/check-store-screenshots.sh "$OUT" 2>&1) || fail "검사: $out"

# 9 반영: 여기서만 fastlane/screenshots/ko 를 바꾼다. 같은 디스크의 임시 폴더에 다 복사한 뒤 폴더째 바꿔치기해,
# 복사가 중간에 실패해도 기존 세트가 지워지지 않는다(ko 에는 검사가 허용하는 스크린샷만 있으므로 폴더째 바꿔도 잃는 파일이 없다).
STAGE="$WORK/dest.new"
OLD="$WORK/dest.old"
rm -rf "$STAGE" "$OLD"
mkdir -p "$STAGE" "$(dirname "$DEST")"
cp "$OUT"/*.png "$STAGE"/ || fail "반영: 임시 폴더로 복사하지 못했습니다 (기존 $DEST 는 그대로)"
if [[ -d $DEST ]]; then
  mv "$DEST" "$OLD" || fail "반영: 기존 $DEST 를 옮기지 못했습니다 (그대로)"
fi
if ! mv "$STAGE" "$DEST"; then
  [[ -d $OLD ]] && mv "$OLD" "$DEST"
  fail "반영: 새 세트를 옮기지 못했습니다 (기존 세트로 되돌림)"
fi
rm -rf "$OLD"
out=$(scripts/check-store-screenshots.sh fastlane/screenshots 2>&1) || fail "반영: $out"

printf '%s\n' "${timings[@]}"
echo "OK $DEST ${#SCREENS[@]}장. git diff 로 바뀐 장을 확인하고 눈으로 확인하세요 (디버그 줄·실제 브랜드·실제 번호·로딩 표시·빈 지도·흰 화면 없음, 라이트, 9:41)"
