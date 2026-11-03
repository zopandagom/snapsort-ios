"""check-store-metadata.py 테스트. make test-scripts 가 실행한다."""

import contextlib
import importlib.util
import io
import shutil
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("check_store_metadata", SCRIPTS / "check-store-metadata.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

VALID = {
    "ko/name.txt": "보관함 - 사진 정리",
    "ko/subtitle.txt": "모바일 쿠폰 만료 알림",
    "ko/keywords.txt": "교환권,영수증,여행",
    "ko/promotional_text.txt": "홍보 문구",
    "ko/description.txt": "설명",
    "ko/support_url.txt": "https://example.com/support/",
    "ko/privacy_url.txt": "https://example.com/privacy/",
    "copyright.txt": "2026 Someone",
    "primary_category.txt": "PHOTO_AND_VIDEO",
}


class CheckStoreMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="store-metadata-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.metadata = self.tmp / "metadata"
        for name, text in VALID.items():
            self.write(name, text)
        self.captions = self.tmp / "captions.tsv"
        self.captions.write_text("# 주석\n01-gifticons\t모바일 쿠폰 만료,\t잊기 전에\n", encoding="utf-8")
        self.support = self.tmp / "site/support/index.html"
        self.support.parent.mkdir(parents=True)
        self.support.write_text("<p>쿠폰 만료 알림</p>", encoding="utf-8")

    def write(self, name, text):
        path = self.metadata / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text + "\n", encoding="utf-8")

    def run_check(self, argv=None):
        stderr = io.StringIO()
        argv = argv or [
            "--metadata", str(self.metadata), "--captions", str(self.captions), "--support", str(self.support)
        ]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            status = checker.main(argv)
        return status, stderr.getvalue()

    def assert_fails(self, message):
        status, stderr = self.run_check()
        self.assertEqual(status, 1, stderr)
        self.assertIn(message, stderr)

    def test_repository_metadata_passes(self):
        status, stderr = self.run_check([])
        self.assertEqual(status, 0, stderr)

    def test_valid_fixture_passes(self):
        status, stderr = self.run_check()
        self.assertEqual(status, 0, stderr)

    def test_fails_on_missing_file(self):
        (self.metadata / "ko/subtitle.txt").unlink()
        self.assert_fails("ko/subtitle.txt 가 없거나 비어 있습니다")

    def test_fails_on_empty_root_file(self):
        self.write("primary_category.txt", "  ")
        self.assert_fails("primary_category.txt 가 없거나 비어 있습니다")

    def test_fails_on_name_over_30_characters(self):
        self.write("ko/name.txt", "가" * 31)
        self.assert_fails("ko/name.txt 가 30자를 넘습니다 (31자)")

    def test_counts_characters_not_bytes_for_limits(self):
        self.write("ko/subtitle.txt", "가" * 30)
        status, stderr = self.run_check()
        self.assertEqual(status, 0, stderr)

    def test_fails_on_promotional_text_over_170_characters(self):
        self.write("ko/promotional_text.txt", "가" * 171)
        self.assert_fails("ko/promotional_text.txt 가 170자를 넘습니다")

    def test_fails_on_description_over_4000_characters(self):
        self.write("ko/description.txt", "가" * 4001)
        self.assert_fails("ko/description.txt 가 4000자를 넘습니다")

    def test_fails_on_release_notes_over_4000_characters_only_when_present(self):
        self.write("ko/release_notes.txt", "가" * 4001)
        self.assert_fails("ko/release_notes.txt 가 4000자를 넘습니다")

    def test_fails_on_keywords_over_100_utf8_bytes(self):
        self.write("ko/keywords.txt", ",".join(["교환권"] * 12))  # 9바이트 × 12 + 쉼표 11 = 119바이트, 36자
        self.assert_fails("ko/keywords.txt 가 100바이트를 넘습니다 (119바이트, UTF-8)")

    def test_fails_on_empty_keyword_item(self):
        self.write("ko/keywords.txt", "교환권,,영수증")
        self.assert_fails("빈 항목")

    def test_fails_on_keyword_repeating_name_or_subtitle_word(self):
        self.write("ko/keywords.txt", "교환권,사진,쿠폰함")
        status, stderr = self.run_check()
        self.assertEqual(status, 1)
        self.assertIn("항목 '사진' 에 이름·부제 낱말이 있습니다: 사진", stderr)
        self.assertIn("항목 '쿠폰함' 에 이름·부제 낱말이 있습니다: 쿠폰", stderr)
        self.assertNotIn("교환권", stderr)

    def test_fails_on_url_without_https(self):
        self.write("ko/support_url.txt", "http://example.com/support/")
        self.assert_fails("ko/support_url.txt 가 https:// 로 시작하지 않습니다")

    def test_fails_on_banned_word_in_metadata(self):
        self.write("ko/description.txt", "기프티콘 만료일을 알려 줍니다")
        self.assert_fails("ko/description.txt 에 '기프티콘' 가 있습니다")

    def test_fails_on_banned_word_in_caption_but_not_in_file_stem(self):
        self.captions.write_text("02-gifticons\t기프티콘 만료,\t잊기 전에\n", encoding="utf-8")
        self.assert_fails("captions.tsv:1 에 '기프티콘' 가 있습니다")

    def test_fails_on_banned_word_in_support_page(self):
        self.support.write_text("<p>기프티콘 카드</p>", encoding="utf-8")
        self.assert_fails("support/index.html 에 '기프티콘' 가 있습니다")

    def test_fails_on_missing_support_page(self):
        self.support.unlink()
        self.assert_fails("지원 페이지가 없습니다")


if __name__ == "__main__":
    unittest.main()
