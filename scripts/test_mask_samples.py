"""mask-samples.py 테스트. make test-scripts 가 실행한다."""

import contextlib
import importlib.util
import io
import json
import re
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
FIXTURE = SCRIPTS.parent / "Projects/Shared/Core/Tests/Fixtures/ClassificationSamples.json"

spec = importlib.util.spec_from_file_location("mask_samples", SCRIPTS / "mask-samples.py")
mask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mask)
KEYWORDS, TIMESTAMP = mask.load_rules()


def run_main(argv):
    """안내·오류 문구를 테스트 출력에 섞지 않고 `main` 을 실행한다."""
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return mask.main(argv)


def masked(line):
    return mask.mask_line(line, KEYWORDS, TIMESTAMP)[0]


class MaskLineTests(unittest.TestCase):
    def test_keeps_keywords_and_spaces_and_masks_the_rest(self):
        self.assertEqual(masked("교환처 스타벅스 강남점"), "교환처 ○○○○ ○○○")
        self.assertEqual(masked("유효기간 2026.12.31"), "유효기간 ○○○○○○○○○○")

    def test_keeps_keyword_read_with_spaces(self):
        self.assertEqual(masked("유효 기간 2026.12.31"), "유효 기간 ○○○○○○○○○○")

    def test_masks_keyword_crossing_space_from_middle_of_word(self):
        """분류기가 세지 않는 자리(앞 단어 중간에서 시작해 공백을 넘음)는 키워드 글자도 가린다."""
        self.assertEqual(masked("몇 시까지 도착해"), "○ ○○○ ○○○")
        self.assertEqual(masked("길 찾기 지 도"), "길 찾기 지 도")

    def test_keeps_keyword_inside_word(self):
        self.assertEqual(masked("신세계상품권"), "○○○상품권")

    def test_keeps_whole_line_chat_timestamp(self):
        self.assertEqual(masked("오후 3:12"), "오후 3:12")
        self.assertEqual(masked("1오후 3:12"), "1오후 3:12")

    def test_masks_timestamp_inside_sentence(self):
        self.assertEqual(masked("미사 오전 11:30"), "○○ ○○ ○○○○○")
        self.assertEqual(masked("9:41"), "○○○○")

    def test_masks_names_phone_numbers_and_codes(self):
        line = masked("홍길동 010-1234-5678 쿠폰번호 1234 5678 9012")
        self.assertEqual(line, "○○○ ○○○○○○○○○○○○○ 쿠폰번호 ○○○○ ○○○○ ○○○○")

    def test_keeps_character_count_for_document_length(self):
        for line in ["Wi-Fi 설정", "👍🏻 좋아요", "e\u0301clair", "👨\u200d👩\u200d👧 가족", "🇰🇷🇯🇵 여행", "🏴\U000E0067\U000E0062\U000E0065\U000E006E\U000E0067\U000E007F 런던"]:
            self.assertEqual(len(mask.clusters(masked(line))), len(mask.clusters(line)), line)
        self.assertEqual(masked("👍🏻 좋아요"), "○ ○○○")
        self.assertEqual(masked("🇰🇷🇯🇵 여행"), "○○ ○○")

    def test_only_keywords_timestamps_and_mask_remain(self):
        line = masked("ABC 합계 9,000 결제금액 9,000 서울시 강남구")
        kept = "".join(c for c in line if not c.isspace() and c != mask.MASK)
        self.assertEqual(kept, "합계결제금액")


class RulesTests(unittest.TestCase):
    def test_reads_keyword_table_and_timestamp_pattern(self):
        self.assertIn("유효기간", KEYWORDS)
        self.assertIn("메시지입력", KEYWORDS)
        self.assertTrue(TIMESTAMP.fullmatch("오후3:12"))

    def test_reads_every_rule_keyword(self):
        """주석·타입 선언 말고 규칙 호출마다 키워드를 읽는다 (규칙 하나를 빠뜨리면 그 키워드가 가려진다)."""
        for keyword in ["교환처", "승인번호", "문자메시지", "장바구니", "길찾기"]:
            self.assertIn(keyword, KEYWORDS)

    def test_fails_when_a_rule_keywords_is_not_a_literal(self):
        """한 규칙의 키워드를 상수 참조로 바꾸면 남은 규칙을 읽어도 실패한다. 주석의 `keywords: [...]` 는 세지 않는다."""
        source = mask.RULES_PATH.read_text(encoding="utf-8")
        literal = re.search(r"keywords: \[\s*\"유효기간\".*?\]", source, re.S)
        self.assertIsNotNone(literal)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ClassificationRules.swift"
            path.write_text(source.replace(literal.group(0), "keywords: gifticonKeywords"), encoding="utf-8")
            with self.assertRaisesRegex(mask.RulesError, "gifticon"):
                mask.load_rules(path)

    def test_fails_when_rules_cannot_be_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ClassificationRules.swift"
            path.write_text("enum ClassificationRules {}", encoding="utf-8")
            with self.assertRaises(mask.RulesError):
                mask.load_rules(path)


class FileTests(unittest.TestCase):
    def test_masked_fixture_samples_are_unchanged(self):
        """시드(직접 만든 글자) 밖의 샘플은 이미 가렸으므로 다시 가려도 그대로이고, 픽스처와 같은 형식으로 쓴다.
        가리지 않은 샘플이 픽스처에 들어오면(이름을 바꾸지 않은 초안 포함) 실패한다.
        키워드 표에서 키워드를 지워도 실패한다. 그때는 실패 메시지의 샘플만 다시 가려 `text` 를 바꾼다 (CONVENTIONS §3)."""
        text = FIXTURE.read_text(encoding="utf-8")
        real = [s for s in json.loads(text) if not s["name"].startswith("시드 · ")]
        result, _ = mask.mask_samples(real, KEYWORDS, TIMESTAMP)
        changed = [before["name"] for before, after in zip(real, result) if before != after]
        self.assertEqual(
            changed,
            [],
            "다시 가리면 달라지는 샘플이 있습니다. 가리지 않은 샘플이 들어왔거나 키워드 표에서 키워드가 빠졌습니다. "
            "이 샘플들만 scripts/mask-samples.py 로 다시 가려 text 를 바꾸세요 (CONVENTIONS §3)",
        )
        for block in mask.format_samples(real).strip("[]\n").split("\n  },\n"):
            self.assertIn(block.strip().rstrip("}").strip(), text)

    def test_writes_masked_draft_in_fixture_key_order(self):
        draft = [
            {
                "asset": {"hasLocation": False, "isScreenshot": True, "pixelHeight": 2556, "pixelWidth": 1179},
                "labels": [{"confidence": 0.9, "identifier": "screenshot"}],
                "name": "앨범 001",
                "predicted": ["gifticon"],
                "text": ["홍길동님", "교환처 스타벅스", "유효기간 2026.12.31"],
            }
        ]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "ClassificationSamples-draft-1.json"
            source.write_text(json.dumps(draft, ensure_ascii=False), encoding="utf-8")
            self.assertEqual(run_main([str(source)]), 0)
            output = (Path(directory) / "ClassificationSamples-draft-1-masked.json").read_text(encoding="utf-8")
        self.assertEqual(
            output,
            "[\n  {\n"
            '    "name": "앨범 001",\n'
            '    "asset": { "hasLocation": false, "isScreenshot": true, "pixelHeight": 2556, "pixelWidth": 1179 },\n'
            '    "labels": [{ "identifier": "screenshot", "confidence": 0.9 }],\n'
            '    "text": ["○○○○", "교환처 ○○○○", "유효기간 ○○○○○○○○○○"],\n'
            '    "predicted": ["gifticon"]\n'
            "  }\n]\n",
        )

    def test_refuses_to_overwrite_input(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "draft.json"
            source.write_text("[]", encoding="utf-8")
            self.assertEqual(run_main([str(source), "-o", str(source)]), 1)
            self.assertEqual(source.read_text(encoding="utf-8"), "[]")

    def test_refuses_to_overwrite_input_through_case_differing_path(self):
        """대소문자를 구분하지 않는 파일시스템(macOS 기본)에서는 대소문자만 다른 경로도 같은 파일이다."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "draft.json"
            source.write_text("[]", encoding="utf-8")
            alias = Path(directory) / "DRAFT.json"
            if not alias.exists():
                self.skipTest("대소문자를 구분하는 파일시스템")
            self.assertEqual(run_main([str(source), "-o", str(alias)]), 1)
            self.assertEqual(source.read_text(encoding="utf-8"), "[]")


if __name__ == "__main__":
    unittest.main()
