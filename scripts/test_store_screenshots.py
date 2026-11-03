"""스토어 스크린샷 합성(store-compose.swift)·검사(check-store-screenshots.sh)·촬영 안정 판정(store-frame.swift)·
촬영 화면 표 테스트. make test-scripts 가 실행한다.

시뮬레이터 촬영 루프 자체는 테스트하지 않는다(make store-screenshots 로 사람이 돌린다). store-frame 은 지어낸 PNG 두 장으로
판정 순서(오류·시스템 표시·빈 화면·다름·같음)와 종료 코드를 확인한다. macOS 의 swift·swiftc·sips 가 필요하다.
"""

import hashlib
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
CAPTIONS = SCRIPTS / "store-captions.tsv"
CHECK = SCRIPTS / "check-store-screenshots.sh"
COMPOSE = SCRIPTS / "store-compose.swift"
SHOOT = SCRIPTS / "store-screenshots.sh"
STORE_SCREENS_SWIFT = ROOT / "Projects/Features/Library/Example/StoreScreenshots.swift"
FRAME_SOURCE = SCRIPTS / "store-frame.swift"
CAPTION_FONT = ROOT / "Projects/Shared/DesignSystem/Resources/Fonts/NanumSquareRoundOTFEB.otf"
WIDTH, HEIGHT = 1320, 2868


def write_png(path, width, height, alpha, pixels=None):
    """PNG 를 표준 라이브러리만으로 쓴다(alpha 면 RGBA, 아니면 RGB).

    pixels 는 위 줄부터의 픽셀 바이트(줄 필터 바이트 없음)이고, 없으면 한 색으로 채운다.
    """
    channels = 4 if alpha else 3
    if pixels is None:
        pixels = bytes([120, 160, 200, 255][:channels]) * (width * height)
    stride = width * channels
    raw = b"".join(b"\x00" + bytes(pixels[y * stride : (y + 1) * stride]) for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)
    Path(path).write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b"")
    )


def striped_pixels(width=WIDTH, height=HEIGHT):
    """줄마다 다른 색 줄무늬 RGBA 픽셀(한 색이면 빈 화면 판정에 걸리므로). 채널은 40 을 더해도 넘치지 않고, 거의 검은색이 없다."""
    pixels = bytearray()
    for y in range(height):
        pixels += bytes([20 + y % 180, 160, 40 + (y * 7) % 160, 255]) * width
    return pixels


def caption_stems(path=CAPTIONS):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    return [line.split("\t")[0] for line in lines if line.strip() and not line.startswith("#")]


def run(args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)


def md5(path):
    return hashlib.md5(Path(path).read_bytes()).hexdigest()


class StoreScreenshotTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = Path(tempfile.mkdtemp(prefix="store-screenshots-fixtures-"))
        cls.good = cls.fixtures / "good.png"
        cls.alpha = cls.fixtures / "alpha.png"
        cls.small = cls.fixtures / "small.png"
        write_png(cls.good, WIDTH, HEIGHT, alpha=False)
        write_png(cls.alpha, WIDTH, HEIGHT, alpha=True)
        write_png(cls.small, 100, 200, alpha=False)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.fixtures)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="store-screenshots-"))
        self.addCleanup(shutil.rmtree, self.tmp)

    def fill(self, folder, stems, source=None):
        folder.mkdir(parents=True, exist_ok=True)
        for stem in stems:
            shutil.copy(source or self.good, folder / f"{stem}.png")


class ComposeTests(StoreScreenshotTestCase):
    STEMS = ["01-home", "02-gifticons"]

    def write_captions(self, text):
        path = self.tmp / "captions.tsv"
        path.write_text(text, encoding="utf-8")
        return path

    def compose(self, captions, raw, out, font=CAPTION_FONT):
        return run(["swift", COMPOSE, captions, raw, out, font])

    def test_writes_opaque_full_size_images_deterministically(self):
        captions = self.write_captions("# 주석\n01-home\t첫 줄\t둘째 줄\n\n02-gifticons\t한 줄만\n")
        raw = self.tmp / "raw"
        self.fill(raw, self.STEMS, source=self.alpha)  # 시뮬레이터 캡처처럼 알파가 있는 입력

        first = self.compose(captions, raw, self.tmp / "out1")
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.compose(captions, raw, self.tmp / "out2")
        self.assertEqual(second.returncode, 0, second.stderr)

        for stem in self.STEMS:
            image = self.tmp / "out1" / f"{stem}.png"
            info = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", image]).stdout
            self.assertIn(f"pixelWidth: {WIDTH}", info)
            self.assertIn(f"pixelHeight: {HEIGHT}", info)
            self.assertIn("hasAlpha: no", info)
            self.assertEqual(md5(image), md5(self.tmp / "out2" / f"{stem}.png"), stem)

    def test_fails_without_writing_when_an_input_has_wrong_size(self):
        captions = self.write_captions("01-home\t첫 줄\n02-gifticons\t첫 줄\n")
        raw = self.tmp / "raw"
        self.fill(raw, ["01-home"])
        self.fill(raw, ["02-gifticons"], source=self.small)

        result = self.compose(captions, raw, self.tmp / "out")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL 합성: 02-gifticons", result.stderr)
        self.assertEqual(list((self.tmp / "out").glob("*.png")), [])

    def test_fails_when_an_input_is_missing(self):
        captions = self.write_captions("01-home\t첫 줄\n02-gifticons\t첫 줄\n")
        raw = self.tmp / "raw"
        self.fill(raw, ["01-home"])

        result = self.compose(captions, raw, self.tmp / "out")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("02-gifticons", result.stderr)

    def test_fails_without_writing_when_caption_font_is_missing(self):
        captions = self.write_captions("01-home\t첫 줄\n")
        raw = self.tmp / "raw"
        self.fill(raw, ["01-home"])

        result = self.compose(captions, raw, self.tmp / "out", font=self.tmp / "없는 글꼴.otf")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL 합성: 캡션 글꼴 파일이 없거나 읽지 못했습니다", result.stderr)
        self.assertEqual(list((self.tmp / "out").glob("*.png")), [])

    def test_fails_without_writing_when_caption_font_is_not_a_font(self):
        captions = self.write_captions("01-home\t첫 줄\n")
        raw = self.tmp / "raw"
        self.fill(raw, ["01-home"])
        broken = self.tmp / "broken.otf"
        broken.write_bytes(b"not a font")

        result = self.compose(captions, raw, self.tmp / "out", font=broken)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL 합성: 캡션 글꼴 파일을 글꼴로 읽지 못했습니다", result.stderr)
        self.assertEqual(list((self.tmp / "out").glob("*.png")), [])

    def test_shoot_script_passes_design_system_caption_font(self):
        text = SHOOT.read_text(encoding="utf-8")
        self.assertIn(f"CAPTION_FONT={CAPTION_FONT.relative_to(ROOT)}", text)
        self.assertTrue(CAPTION_FONT.is_file(), CAPTION_FONT)

    def test_fails_when_caption_does_not_fit(self):
        captions = self.write_captions("01-home\t" + "아주 긴 캡션 문구" * 6 + "\n")
        raw = self.tmp / "raw"
        self.fill(raw, ["01-home"])

        result = self.compose(captions, raw, self.tmp / "out")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("01-home 캡션이 너무 깁니다", result.stderr)


class CheckTests(StoreScreenshotTestCase):
    def check(self, folder, captions=None):
        env = dict(os.environ)
        if captions is not None:
            env["STORE_CAPTIONS"] = str(captions)
        return run([CHECK, folder], env=env)

    def assert_fails(self, result, message):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("FAIL 스토어 스크린샷", result.stderr)
        self.assertIn(message, result.stderr)

    def test_passes_complete_flat_folder(self):
        self.fill(self.tmp, caption_stems())

        result = self.check(self.tmp)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OK 스토어 스크린샷 6장", result.stdout)

    def test_passes_complete_language_folder(self):
        self.fill(self.tmp / "ko", caption_stems())
        (self.tmp / "ko" / ".gitkeep").touch()

        self.assertEqual(self.check(self.tmp).returncode, 0)

    def test_fails_on_empty_language_folder(self):
        (self.tmp / "ko").mkdir()
        (self.tmp / "ko" / ".gitkeep").touch()

        self.assert_fails(self.check(self.tmp), "없음: ko/01-home.png")

    def test_fails_on_missing_image(self):
        self.fill(self.tmp / "ko", caption_stems()[:5])

        self.assert_fails(self.check(self.tmp), "없음: ko/06-cleanup.png")

    def test_fails_on_extra_image(self):
        self.fill(self.tmp / "ko", caption_stems() + ["07-extra"])

        self.assert_fails(self.check(self.tmp), "여분: ko/07-extra.png")

    def test_fails_on_wrong_name(self):
        stems = caption_stems()
        self.fill(self.tmp / "ko", stems[:5] + ["06-clean"])

        self.assert_fails(self.check(self.tmp), "여분: ko/06-clean.png")

    def test_fails_on_other_language_folder(self):
        self.fill(self.tmp / "ko", caption_stems())
        self.fill(self.tmp / "en-US", ["01-home"])

        self.assert_fails(self.check(self.tmp), "여분: en-US/01-home.png")

    def test_fails_on_wrong_size(self):
        stems = caption_stems()
        self.fill(self.tmp / "ko", stems)
        shutil.copy(self.small, self.tmp / "ko" / f"{stems[2]}.png")

        self.assert_fails(self.check(self.tmp), f"ko/{stems[2]}.png 이 1320x2868 가 아닙니다 (100x200)")

    def test_fails_on_alpha(self):
        stems = caption_stems()
        self.fill(self.tmp / "ko", stems)
        shutil.copy(self.alpha, self.tmp / "ko" / f"{stems[0]}.png")

        self.assert_fails(self.check(self.tmp), "알파 채널")

    def test_fails_when_caption_list_is_not_six(self):
        captions = self.tmp / "captions.tsv"
        captions.write_text("# 주석\n01-home\t첫 줄\n", encoding="utf-8")
        self.fill(self.tmp / "out", ["01-home"])

        self.assert_fails(self.check(self.tmp / "out", captions), "캡션 목록이 6장이 아닙니다")

    def test_fails_when_caption_stems_repeat(self):
        captions = self.tmp / "captions.tsv"
        captions.write_text("".join(f"0{i}-home\t줄\n" for i in [1, 2, 3, 4, 5]) + "01-home\t줄\n", encoding="utf-8")

        self.assert_fails(self.check(self.tmp, captions), "겹치는 줄기")

    def test_fails_when_caption_stem_has_bad_format(self):
        captions = self.tmp / "captions.tsv"
        captions.write_text("Home\t줄\n", encoding="utf-8")

        self.assert_fails(self.check(self.tmp, captions), "줄기 형식")

    def test_repository_screenshots_pass(self):
        """레포에는 항상 업로드할 수 있는 6장이 있어야 한다(출시 lane 이 같은 검사로 멈춘다)."""
        result = self.check(ROOT / "fastlane/screenshots")

        self.assertEqual(result.returncode, 0, result.stderr)


class FrameTests(unittest.TestCase):
    """store-frame: 연속 캡처 두 장의 안정 판정. 정확히 16/17 경계는 색공간 변환 반올림(±1)으로 흔들릴 수 있어 시험하지 않는다."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="store-frame-"))
        cls.frame = cls.tmp / "store-frame"
        built = run(["swiftc", "-O", FRAME_SOURCE, "-o", cls.frame])
        if built.returncode != 0:
            shutil.rmtree(cls.tmp)
            raise AssertionError(f"store-frame.swift 컴파일 실패: {built.stderr}")
        cls.base = striped_pixels()
        cls.before = cls.tmp / "before.png"
        write_png(cls.before, WIDTH, HEIGHT, alpha=True, pixels=cls.base)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def image(self, name, pixels, width=WIDTH, height=HEIGHT):
        path = self.tmp / f"{self.id().rsplit('.', 1)[-1]}-{name}.png"
        write_png(path, width, height, alpha=True, pixels=pixels)
        return path

    def compare(self, before, after):
        return run([self.frame, before, after])

    def assert_verdict(self, result, code, text):
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertIn(text, result.stdout)
        self.assertEqual(len(result.stdout.splitlines()), 1, result.stdout)

    @staticmethod
    def paint(pixels, xs, ys, color):
        for y in ys:
            for x in xs:
                i = (y * WIDTH + x) * 4
                pixels[i : i + 4] = bytes(color)

    def test_same_images_are_stable(self):
        self.assert_verdict(self.compare(self.before, self.image("same", self.base)), 0, "같음")

    def test_small_noise_everywhere_is_stable(self):
        noisy = bytearray(self.base)
        for i in range(len(noisy)):
            if i % 4 != 3:
                noisy[i] += 10

        self.assert_verdict(self.compare(self.before, self.image("noisy", noisy)), 0, "같음")

    def test_one_pixel_change_beyond_tolerance_differs(self):
        changed = bytearray(self.base)
        i = (1500 * WIDTH + 600) * 4
        changed[i] += 40

        self.assert_verdict(self.compare(self.before, self.image("pixel", changed)), 1, "다름: 픽셀 1개 (y 1500~1500)")

    def test_changed_square_reports_rows(self):
        changed = bytearray(self.base)
        self.paint(changed, range(300, 340), range(1000, 1040), [250, 20, 250, 255])

        self.assert_verdict(self.compare(self.before, self.image("square", changed)), 1, "(y 1000~1039)")

    def test_dynamic_island_on_later_image_is_system_overlay(self):
        island = bytearray(self.base)
        self.paint(island, range(470, 850), range(40, 160), [0, 0, 0, 255])

        result = self.compare(self.before, self.image("island", island))

        self.assert_verdict(result, 3, "시스템 표시: 화면 위 가운데 검은 픽셀 45600개")

    def test_dynamic_island_only_on_earlier_image_differs(self):
        island = bytearray(self.base)
        self.paint(island, range(470, 850), range(40, 160), [0, 0, 0, 255])

        self.assert_verdict(self.compare(self.image("island", island), self.before), 1, "다름:")

    def test_blank_launch_screen_fails_even_when_identical(self):
        white = bytes([255, 255, 255, 255]) * (WIDTH * HEIGHT)
        blank = self.image("white", white)

        self.assert_verdict(self.compare(blank, blank), 4, "빈 화면: 한 색이 1.00")

    def test_wrong_size_is_an_error(self):
        small = self.image("small", striped_pixels(100, 200), width=100, height=200)

        result = self.compare(self.before, small)

        self.assert_verdict(result, 2, f"오류: {small}: 1320x2868 가 아닙니다 (100x200)")

    def test_missing_file_is_an_error(self):
        missing = self.tmp / "missing.png"

        self.assert_verdict(self.compare(self.before, missing), 2, f"오류: {missing}: 파일이 없습니다")

    def test_wrong_argument_count_is_an_error(self):
        self.assert_verdict(run([self.frame, self.before]), 2, "오류: 인자")


class ScreenTableTests(unittest.TestCase):
    def test_shoot_script_screens_match_captions(self):
        result = run([SHOOT, "--list"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([line.split("\t")[0] for line in result.stdout.splitlines()], caption_stems())

    def test_shoot_script_keys_match_example_store_screens(self):
        # 키가 틀리면 Example 이 조용히 홈 화면을 띄워, 다른 캡션을 단 홈이 모든 검사를 통과한다. 순서까지 대조한다.
        source = STORE_SCREENS_SWIFT.read_text(encoding="utf-8")
        body = re.search(r"enum StoreScreen\b[^{]*\{(.*?)\n  static var current", source, re.S)
        self.assertIsNotNone(body, "StoreScreenshots.swift 에서 enum StoreScreen 을 찾지 못했습니다")
        cases = re.findall(r"^  case (\w+)$", body.group(1), re.M)
        result = run([SHOOT, "--list"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([line.split("\t")[1] for line in result.stdout.splitlines()], cases)

    def test_captions_have_six_entries_with_one_or_two_lines(self):
        lines = [
            line
            for line in CAPTIONS.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")
        ]
        self.assertEqual(len(lines), 6)
        for line in lines:
            self.assertIn(len(line.split("\t")), (2, 3), line)


if __name__ == "__main__":
    unittest.main()
