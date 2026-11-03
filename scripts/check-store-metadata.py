#!/usr/bin/env python3
"""스토어 메타데이터·캡션·지원 페이지 문구를 검사한다 (docs/CONVENTIONS.md §5). make test-scripts 가 실제 파일로 돌린다.

사용: scripts/check-store-metadata.py [--metadata DIR] [--captions FILE] [--support FILE]
기본값은 레포의 fastlane/metadata, scripts/store-captions.tsv, site/support/index.html 이다.

검사:
- 필요한 파일이 있고 비어 있지 않음(ko/ 의 name·subtitle·keywords·promotional_text·description·support_url·privacy_url, 루트의 copyright·primary_category).
- 글자 수: name·subtitle ≤ 30, promotional_text ≤ 170, description·release_notes(있으면) ≤ 4000.
- keywords: UTF-8 ≤ 100 바이트(ASC 는 "100 bytes", 인코딩은 미확인이라 보수적으로), 쉼표로 나눈 항목에 빈 항목 없음,
  항목이 이름·부제의 낱말(공백·쉼표·하이픈으로 나눔, 2글자 이상)과 같거나 그 낱말을 포함하면 실패(이미 검색에 걸리는 낱말의 중복).
- URL 파일(*_url.txt)은 https:// 로 시작.
- '기프티콘'(다른 회사 서비스 이름)이 스토어 문구(URL 파일 말고 모든 .txt)·캡션 열·지원 페이지에 있으면 실패.
  앱 화면의 카테고리 이름은 범위 밖이라 스크린샷 그림은 검사하지 않는다.
키워드 항목 "2자 초과" 규칙은 글자/바이트 기준이 확인되지 않아 검사하지 않는다.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGUAGE = "ko"
REQUIRED_LOCALIZED = [
    "name",
    "subtitle",
    "keywords",
    "promotional_text",
    "description",
    "support_url",
    "privacy_url",
]
REQUIRED_ROOT = ["copyright", "primary_category"]
CHAR_LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "description": 4000, "release_notes": 4000}
KEYWORDS_BYTE_LIMIT = 100
BANNED_WORDS = ["기프티콘"]


def read(path):
    return path.read_text(encoding="utf-8").strip()


def words(text):
    return [w for w in re.split(r"[\s,\-]+", text) if len(w) >= 2]


def check_metadata(metadata):
    errors = []
    localized = metadata / LANGUAGE
    for key in REQUIRED_LOCALIZED:
        path = localized / f"{key}.txt"
        if not path.is_file() or not read(path):
            errors.append(f"{LANGUAGE}/{key}.txt 가 없거나 비어 있습니다")
    for key in REQUIRED_ROOT:
        path = metadata / f"{key}.txt"
        if not path.is_file() or not read(path):
            errors.append(f"{key}.txt 가 없거나 비어 있습니다")

    for key, limit in CHAR_LIMITS.items():
        path = localized / f"{key}.txt"
        if path.is_file() and len(read(path)) > limit:
            errors.append(f"{LANGUAGE}/{key}.txt 가 {limit}자를 넘습니다 ({len(read(path))}자)")

    keywords_path = localized / "keywords.txt"
    if keywords_path.is_file():
        keywords = read(keywords_path)
        size = len(keywords.encode("utf-8"))
        if size > KEYWORDS_BYTE_LIMIT:
            errors.append(f"{LANGUAGE}/keywords.txt 가 {KEYWORDS_BYTE_LIMIT}바이트를 넘습니다 ({size}바이트, UTF-8)")
        items = [item.strip() for item in keywords.split(",")]
        if any(not item for item in items):
            errors.append(f"{LANGUAGE}/keywords.txt 에 빈 항목이 있습니다")
        taken = set()
        for key in ("name", "subtitle"):
            path = localized / f"{key}.txt"
            if path.is_file():
                taken.update(words(read(path)))
        for item in items:
            hits = sorted(word for word in taken if word in item)
            if hits:
                errors.append(f"{LANGUAGE}/keywords.txt 항목 '{item}' 에 이름·부제 낱말이 있습니다: {', '.join(hits)}")

    for path in sorted(metadata.rglob("*.txt")):
        relative = path.relative_to(metadata)
        text = read(path)
        if path.name.endswith("_url.txt"):
            if text and not text.startswith("https://"):
                errors.append(f"{relative} 가 https:// 로 시작하지 않습니다")
            continue
        errors += banned_word_errors(text, str(relative))
    return errors


def banned_word_errors(text, label):
    return [f"{label} 에 '{word}' 가 있습니다 (스토어 문구에서는 '모바일 쿠폰'·'쿠폰')" for word in BANNED_WORDS if word in text]


def check_captions(captions):
    if not captions.is_file():
        return [f"캡션 파일이 없습니다: {captions}"]
    errors = []
    for number, line in enumerate(captions.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        text = "\t".join(line.split("\t")[1:])  # 첫 열(파일 이름 줄기)은 스토어에 보이지 않는다
        errors += banned_word_errors(text, f"{captions.name}:{number}")
    return errors


def check_support(support):
    if not support.is_file():
        return [f"지원 페이지가 없습니다: {support}"]
    return banned_word_errors(support.read_text(encoding="utf-8"), str(support.relative_to(support.parents[1])))


def main(argv=None):
    parser = argparse.ArgumentParser(description="스토어 메타데이터·캡션·지원 페이지 문구 검사")
    parser.add_argument("--metadata", type=Path, default=ROOT / "fastlane/metadata")
    parser.add_argument("--captions", type=Path, default=ROOT / "scripts/store-captions.tsv")
    parser.add_argument("--support", type=Path, default=ROOT / "site/support/index.html")
    args = parser.parse_args(argv)

    errors = check_metadata(args.metadata) + check_captions(args.captions) + check_support(args.support)
    if errors:
        for error in errors:
            print(f"FAIL 스토어 메타데이터: {error}", file=sys.stderr)
        return 1
    print("OK 스토어 메타데이터")
    return 0


if __name__ == "__main__":
    sys.exit(main())
