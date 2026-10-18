#!/usr/bin/env python3
"""기록 도구 샘플 초안의 OCR 줄을 가려 픽스처 형식으로 쓴다 (docs/CONVENTIONS.md §3).

사용: scripts/mask-samples.py <초안.json> [-o <출력.json>]
출력을 주지 않으면 입력 옆에 `<입력 이름>-masked.json` 으로 쓴다 (`ClassificationSamples-draft-*.json` 이면 .gitignore 에 걸린다).

가리는 규칙: 공백과 분류 키워드(Core `ClassificationRules` 키워드 표)만 남기고 모든 글자를 `○` 로 바꾼다. 글자 수는 유지한다.
한 줄 전체가 말풍선 시각(`chatTimestampPattern`, 예: "오후 3:12")인 줄은 대화 캡처 판정에 쓰이므로 그대로 남긴다.
남긴 글자와 공백 위치가 원문과 같고 `○` 는 키워드에 없으므로, 가린 뒤에도 규칙 분류기의 키워드·시각 판정은 원문과 같다.
문서 글자 수도 같게 글자 하나를 `○` 하나로 바꾸지만, 글자 나누기는 Swift `Character` 의 근사다 (`clusters`).
키워드와 시각 패턴은 ClassificationRules.swift 에서 읽는다. 읽지 못하면 아무것도 쓰지 않고 실패한다.
"""

import argparse
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

MASK = "○"
RULES_PATH = Path(__file__).resolve().parent.parent / "Projects/Shared/Core/Sources/ClassificationRules.swift"

# 픽스처 실기기 샘플의 키 순서. 초안은 키를 정렬해 쓰므로 샘플·라벨 키는 픽스처 순서로 바꾸고 asset 은 정렬 순서 그대로 둔다.
# 여기 없는 키는 뒤에 붙인다.
SAMPLE_KEYS = ["name", "asset", "labels", "text", "ocrSkipped", "predicted", "expected", "knownIssue"]
ASSET_KEYS = ["hasLocation", "isScreenshot", "pixelHeight", "pixelWidth"]
LABEL_KEYS = ["identifier", "confidence"]


class RulesError(Exception):
    pass


def load_rules(path=RULES_PATH):
    """ClassificationRules.swift 에서 키워드 목록과 말풍선 시각 패턴을 읽는다."""
    source = path.read_text(encoding="utf-8")
    blocks = re.findall(r"keywords:\s*\[(.*?)\]", source, re.S)
    keywords = sorted({k for block in blocks for k in re.findall(r'"([^"]+)"', block)})
    if len(blocks) < 6 or len(keywords) < 30:
        raise RulesError(f"키워드 표를 읽지 못했습니다 (블록 {len(blocks)}개, 키워드 {len(keywords)}개): {path}")
    pattern = re.search(r"chatTimestampPattern:.*?#/(.*?)/#", source)
    if not pattern:
        raise RulesError(f"chatTimestampPattern 을 읽지 못했습니다: {path}")
    return keywords, re.compile(pattern.group(1))


def clusters(text):
    """글자 단위로 나눈다. Swift `Character`(자소 클러스터)와 같게 세려고 결합 문자·이모지 이음·피부색·태그 문자를 앞 글자에 붙이고
    국기(지역 표시 문자 두 개)를 한 글자로 묶는다. 이 밖의 클러스터 규칙은 다루지 않는다 (근사, OCR 줄에 드물다)."""
    result = []
    joins_next = False
    pending_flag = False
    for char in unicodedata.normalize("NFC", text):
        code = ord(char)
        is_regional = 0x1F1E6 <= code <= 0x1F1FF
        attaches = (
            joins_next
            or (is_regional and pending_flag)
            or unicodedata.category(char) in ("Mn", "Me", "Mc")
            or code == 0x200D
            or 0xFE00 <= code <= 0xFE0F
            or 0x1F3FB <= code <= 0x1F3FF
            or 0xE0020 <= code <= 0xE007F
        )
        if attaches and result:
            result[-1] += char
        else:
            result.append(char)
        joins_next = code == 0x200D
        # 지역 표시 문자는 두 개씩 짝지어 국기 하나가 된다. 짝을 이루면 다음 지역 표시 문자는 새 글자다.
        pending_flag = is_regional and not (attaches and pending_flag)
    return result


def normalize(text):
    """`ClassificationRules.normalize` 와 같다: 공백을 지우고 소문자로."""
    return "".join(c for c in clusters(text.lower()) if not c.isspace())


def mask_line(line, keywords, timestamp):
    if timestamp.fullmatch(normalize(line)):
        return line, True
    chars = clusters(line)
    # 공백을 지운 글자열과 원래 위치. 키워드는 공백을 무시하고 찾으므로 공백을 넘어 걸린 것도 남긴다.
    positions = [i for i, c in enumerate(chars) if not c.isspace()]
    compact = [chars[i].lower() for i in positions]
    keep = set()
    for keyword in keywords:
        word = clusters(keyword)
        for start in range(len(compact) - len(word) + 1):
            if compact[start : start + len(word)] == word:
                keep.update(positions[start : start + len(word)])
    masked = "".join(c if c.isspace() or i in keep else MASK for i, c in enumerate(chars))
    return masked, False


def mask_samples(samples, keywords, timestamp):
    """`text` 를 가린 샘플 목록과 남긴 시각 줄 수를 돌려준다."""
    kept_timestamps = 0
    result = []
    for sample in samples:
        sample = dict(sample)
        lines = []
        for line in sample.get("text", []):
            masked, is_timestamp = mask_line(line, keywords, timestamp)
            kept_timestamps += is_timestamp
            lines.append(masked)
        if "text" in sample:
            sample["text"] = lines
        result.append(sample)
    return result, kept_timestamps


def ordered(obj, keys):
    return {k: obj[k] for k in keys if k in obj} | {k: v for k, v in obj.items() if k not in keys}


def compact(value):
    """픽스처 형식의 한 줄 값: 객체는 `{ "k": v }`, 배열은 `[a, b]`."""
    if isinstance(value, dict):
        if not value:
            return "{}"
        return "{ " + ", ".join(f"{json.dumps(k, ensure_ascii=False)}: {compact(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "[" + ", ".join(compact(v) for v in value) + "]"
    return json.dumps(value, ensure_ascii=False)


def format_samples(samples):
    """픽스처(`ClassificationSamples.json`)와 같은 형식: 샘플마다 키 한 줄씩."""
    blocks = []
    for sample in samples:
        sample = ordered(sample, SAMPLE_KEYS)
        if isinstance(sample.get("asset"), dict):
            sample["asset"] = ordered(sample["asset"], ASSET_KEYS)
        if isinstance(sample.get("labels"), list):
            sample["labels"] = [ordered(label, LABEL_KEYS) for label in sample["labels"]]
        body = ",\n".join(f"    {json.dumps(k, ensure_ascii=False)}: {compact(v)}" for k, v in sample.items())
        blocks.append("  {\n" + body + "\n  }")
    return "[\n" + ",\n".join(blocks) + "\n]\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="샘플 초안의 OCR 줄을 가려 픽스처 형식으로 쓴다.")
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args(argv)

    try:
        keywords, timestamp = load_rules()
    except RulesError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    samples = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(samples, list) or not all(isinstance(s, dict) for s in samples):
        print("error: 샘플 배열이 아닙니다", file=sys.stderr)
        return 1

    masked, kept_timestamps = mask_samples(samples, keywords, timestamp)
    output = args.output or args.input.with_name(f"{args.input.stem}-masked.json")
    # macOS 기본 파일시스템은 대소문자를 구분하지 않아 경로 문자열로는 같은 파일인지 알 수 없으므로, 있으면 파일 자체로 비교한다.
    if output.resolve() == args.input.resolve() or (output.exists() and os.path.samefile(output, args.input)):
        print("error: 출력이 입력과 같습니다. 원본 초안을 남기려고 덮어쓰지 않습니다", file=sys.stderr)
        return 1
    output.write_text(format_samples(masked), encoding="utf-8")
    lines = sum(len(s.get("text", [])) for s in masked)
    print(f"샘플 {len(masked)}개, OCR 줄 {lines}개를 가렸습니다 (그대로 둔 말풍선 시각 줄 {kept_timestamps}개) → {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
