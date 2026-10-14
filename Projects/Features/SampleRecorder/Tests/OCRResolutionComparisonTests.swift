#if DEBUG
  import Core
  import CoreGraphics
  import Foundation
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// OCR 해상도 비교의 입력 크기·줄이기·순서·텍스트 지표.
  struct OCRResolutionComparisonTests {
    // MARK: - 줄일 크기

    @Test("상한 이하인 이미지는 줄이지 않는다(같은 입력)")
    func keepsImagesWithinCap() {
      #expect(OCRResolution.downscaledSize(width: 1632, height: 1224, maxPixelCount: 1632 * 1224) == nil)
      #expect(OCRResolution.downscaledSize(width: 1179, height: 2556, maxPixelCount: 2304 * 1728) == nil)
    }

    @Test(
      "상한보다 크면 비율을 지켜 픽셀 수가 상한 이하가 되게 줄이고, 긴 변은 원본 로더와 같은 식이다",
      arguments: [
        (4032, 3024, 1632 * 1224, 1632, 1224),
        (4032, 3024, 1152 * 864, 1152, 864),
        // 세로로 긴 스크롤 캡처는 높이가 긴 변이다.
        (1179, 10000, 1632 * 1224, 485, 4116),
      ]
    )
    func downscalesWithinCap(width: Int, height: Int, cap: Int, expectedWidth: Int, expectedHeight: Int) throws {
      let size = try #require(OCRResolution.downscaledSize(width: width, height: height, maxPixelCount: cap))

      #expect(size.width == expectedWidth)
      #expect(size.height == expectedHeight)
      #expect(size.width * size.height <= cap)
      // ImageLoader.maxPixelLength 와 같은 식.
      let longSide = Double(max(width, height))
      let expectedLong = (longSide * (Double(cap) / Double(width * height)).squareRoot()).rounded(.down)
      #expect(Double(max(size.width, size.height)) == expectedLong)
      #expect(abs(Double(size.width) / Double(size.height) - Double(width) / Double(height)) < 0.01)
    }

    // MARK: - 줄이기

    @Test("줄인 이미지는 계산한 크기이고 방향을 유지하며 대체 버전 표시가 없다")
    func downscalesImage() throws {
      let image = AnalysisImage.stub(width: 400, height: 300, orientation: .right, isLocalFallback: true)
      let size = try #require(OCRResolution.downscaledSize(width: 400, height: 300, maxPixelCount: 30000))

      let scaled = try #require(OCRResolution.downscale(image, to: size))

      #expect(scaled.cgImage.width == size.width)
      #expect(scaled.cgImage.height == size.height)
      #expect(scaled.orientation == .right)
      #expect(!scaled.isLocalFallback)
      #expect(scaled.cgImage.colorSpace?.model == .rgb)
    }

    @Test("RGB 가 아닌(회색조) 원본은 sRGB 로 줄인다")
    func downscalesGrayscaleToSRGB() throws {
      let context = try #require(CGContext(
        data: nil,
        width: 40,
        height: 30,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ))
      context.setFillColor(gray: 0.5, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
      let source = try #require(context.makeImage())

      let scaled = try #require(OCRResolution.downscale(
        AnalysisImage(cgImage: source, orientation: .left),
        to: (20, 15)
      ))

      #expect((scaled.cgImage.width, scaled.cgImage.height) == (20, 15))
      #expect(scaled.cgImage.colorSpace?.model == .rgb)
      #expect(scaled.cgImage.colorSpace?.name == CGColorSpace.sRGB)
      #expect(scaled.orientation == .left)
    }

    @Test("원본 색 공간으로 8bit 비트맵을 만들 수 없으면 sRGB 로 다시 시도한다")
    func retriesWithSRGB() throws {
      let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
      // 전제: 확장 범위 색 공간으로는 8bit 비트맵을 만들 수 없다(그래야 재시도 경로를 탄다).
      let eightBit = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
      try #require(eightBit == nil)
      let context = try #require(CGContext(
        data: nil,
        width: 40,
        height: 30,
        bitsPerComponent: 16,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
          | CGImageByteOrderInfo.order16Little.rawValue
      ))
      context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
      let source = try #require(context.makeImage())
      #expect(source.colorSpace?.model == .rgb)

      let scaled = try #require(OCRResolution.downscale(AnalysisImage(cgImage: source, orientation: .up), to: (20, 15)))

      #expect((scaled.cgImage.width, scaled.cgImage.height) == (20, 15))
      #expect(scaled.cgImage.colorSpace?.name == CGColorSpace.sRGB)
    }

    // MARK: - 순서

    @Test(
      "OCR 순서는 처리 순서마다 한 칸씩 왼쪽으로 돌고, 변형 수 주기로 돌아온다",
      arguments: [
        (0, [0, 1, 2, 3, 4]),
        (1, [1, 2, 3, 4, 0]),
        (4, [4, 0, 1, 2, 3]),
        (5, [0, 1, 2, 3, 4]),
        (7, [2, 3, 4, 0, 1]),
      ]
    )
    func rotatesOrder(index: Int, expected: [Int]) {
      #expect(OCRResolution.variantOrder(index: index, variantCount: 5) == expected)
    }

    // MARK: - 글자 일치 수

    @Test("줄 순서·줄 나눔·공백·대소문자·유니코드 정규화가 달라도 기준 글자를 모두 찾는다")
    func matchesCharactersIgnoringLayout() {
      let baseline = OCRTextMetrics(lines: ["Hello World", "쿠폰 123", "\u{1112}\u{1161}\u{11AB}"])
      let variant = OCRTextMetrics(lines: ["한", "쿠폰123", "hello", "WOR LD"])

      #expect(baseline.charCount == 16)
      #expect(baseline.matchedCharCount(in: variant) == 16)
    }

    @Test("빠진 글자와 잘못 읽은 글자만큼 줄고, 변형 글자가 더 많아도 기준 글자 수를 넘지 않는다")
    func countsMissingAndMisreadCharacters() {
      #expect(OCRTextMetrics(lines: ["hello world"]).matchedCharCount(in: OCRTextMetrics(lines: ["hello"])) == 5)
      // 3 → 8 오독은 3 을 놓친 것이다.
      #expect(OCRTextMetrics(lines: ["2023"]).matchedCharCount(in: OCRTextMetrics(lines: ["2028"])) == 3)
      #expect(OCRTextMetrics(lines: ["ab"]).matchedCharCount(in: OCRTextMetrics(lines: ["aabbcc"])) == 2)
    }

    @Test("기준 글자가 없으면 0/0 이다(재현율 없음)")
    func emptyBaselineHasNoCharacters() {
      let baseline = OCRTextMetrics(lines: [" "])

      #expect(baseline.charCount == 0)
      #expect(baseline.matchedCharCount(in: OCRTextMetrics(lines: ["abc"])) == 0)
    }

    // MARK: - 날짜·긴 숫자열

    @Test("연도가 있는 점·하이픈·한글 날짜를 찾고, 날짜는 긴 숫자열로 세지 않는다")
    func findsDates() {
      let metrics = OCRTextMetrics(lines: [
        "유효기간 2026.12.31", "2026-12-31", "26.12.31", "2026년 12월 31일", "12/31", "20261231",
        "2026.1.5", "2026.01.05", "26.1.5", "2026년 1월 5일",
      ])

      // 압축 날짜(20261231)와 한 자리·0 패딩 날짜도 날짜다.
      #expect(metrics.dateCount == 9)
      #expect(metrics.longNumberCount == 0)
    }

    @Test("공백·하이픈으로 나뉜 10자리 이상 숫자열을 찾는다")
    func findsLongNumbers() {
      let metrics = OCRTextMetrics(lines: ["쿠폰번호 1234 5678 9012", "1234-5678-90", "123456789"])

      #expect(metrics.longNumberCount == 2)
      #expect(metrics.dateCount == 0)
    }

    @Test("날짜 뒤의 시각은 숫자열이 아니다")
    func timeAfterDateIsNotLongNumber() {
      let metrics = OCRTextMetrics(lines: ["2026-12-31 10:30", "2026.12.31 10:30", "2026년 12월 31일 10:30"])

      #expect(metrics.dateCount == 3)
      #expect(metrics.longNumberCount == 0)
      #expect(OCRTextMetrics(lines: ["2026-12-31 10:30"]).longNumberCount == 0)
    }

    @Test("하이픈 기간의 두 날짜는 숫자열로 이어지지 않는다")
    func hyphenRangeIsTwoDates() {
      let metrics = OCRTextMetrics(lines: ["2026-01-01 - 2026-12-31"])

      #expect(metrics.dateCount == 2)
      #expect(metrics.longNumberCount == 0)
    }

    @Test(
      "공백 없는 기간도 두 날짜를 모두 찾고 숫자열로 남기지 않는다",
      arguments: [
        "2026.01.01-2026.12.31", "2026-01-01-2026-12-31", "2026/01/01-2026/12/31", "26.01.01-26.12.31",
        "20260101-20261231", "2026.01.01 - 2026.12.31", "2026.01.01~2026.12.31",
      ]
    )
    func findsBothDatesOfRange(line: String) {
      let metrics = OCRTextMetrics(lines: [line])

      #expect(metrics.dateCount == 2)
      #expect(metrics.longNumberCount == 0)
    }

    @Test(
      "연도·월·일 범위 밖은 날짜가 아니다",
      arguments: [
        ("12-34-56-78-90", 1),
        ("12-34-56-12-31", 1),
        ("3000-10-20", 0),
        ("2026년 13월 40일", 0),
        ("2026.00.10", 0),
        ("2026.12.00", 0),
      ]
    )
    func outOfRangeIsNotDate(line: String, longNumberCount: Int) {
      let metrics = OCRTextMetrics(lines: [line])

      #expect(metrics.dateCount == 0)
      #expect(metrics.longNumberCount == longNumberCount)
    }

    @Test("한 자리 일 뒤에 시각이 와도 일에 시각 숫자가 붙지 않는다")
    func singleDigitDayBeforeTime() {
      let baseline = OCRTextMetrics(lines: ["2026.1.5 10:30", "2026-12-3 10:30"])

      #expect(baseline.dates == ["2026.1.5": 1, "2026-12-3": 1])
      #expect(baseline.missingDates(in: OCRTextMetrics(lines: ["2026.1.5", "2026-12-3"])) == 0)
      #expect(baseline.longNumberCount == 0)
    }

    @Test("숫자 중간의 2자리 연도 형식은 날짜가 아니다")
    func businessNumberIsNotDate() {
      let metrics = OCRTextMetrics(lines: ["사업자번호 123-45-67890"])

      #expect(metrics.dateCount == 0)
      #expect(metrics.longNumbers == ["1234567890": 1])
    }

    @Test("압축 날짜 뒤의 압축 시각은 숫자열이 아니고, 숫자 사이의 8자리는 날짜가 아니다")
    func compactDate() {
      let withTime = OCRTextMetrics(lines: ["20261231 103000"])
      #expect(withTime.dates == ["20261231": 1])
      #expect(withTime.longNumberCount == 0)

      let embedded = OCRTextMetrics(lines: ["1234202612315678"])
      #expect(embedded.dateCount == 0)
      #expect(embedded.longNumberCount == 1)
    }

    @Test("띄어쓰기가 흔들려도 같은 숫자열이다")
    func spacingDoesNotSplitLongNumber() {
      let baseline = OCRTextMetrics(lines: ["1234 5678 9012"])

      #expect(baseline.missingLongNumbers(in: OCRTextMetrics(lines: ["1234 56789012"])) == 0)
    }

    @Test("연결자 종류가 바뀌면 사슬을 끊고 다음 덩어리가 새 사슬을 시작한다")
    func connectorKindChangeSplitsChain() {
      let metrics = OCRTextMetrics(lines: ["02-123-4567 123-45-67890"])

      #expect(metrics.longNumbers == ["1234567890": 1])
      #expect(metrics.missingLongNumbers(in: OCRTextMetrics(lines: ["1234567890"])) == 0)
    }

    @Test(
      "공백·하이픈으로 묶은 숫자는 한 숫자열이고, 쉼표 금액은 숫자열이 아니다",
      arguments: [
        ("1234 5678 9012", 1),
        ("1234-5678-9012-3456", 1),
        ("8 801234 567890", 1),
        ("8801234567890", 1),
        ("010-1234-5678", 1),
        ("1,234,567,890", 0),
      ]
    )
    func groupsNumbers(line: String, expected: Int) {
      #expect(OCRTextMetrics(lines: [line]).longNumberCount == expected)
    }

    @Test("분해형(NFD) 년월일 줄도 날짜로 찾는다")
    func findsDecomposedKoreanDate() {
      let decomposed = "2026년 12월 31일".decomposedStringWithCanonicalMapping

      #expect(OCRTextMetrics(lines: [decomposed]).dates == ["2026년12월31일": 1])
    }

    @Test("값 다중집합 차로 놓친 날짜·숫자열을 세어, 개수가 같아도 한 자리 오독은 놓친 것이다")
    func countsMissingValues() {
      let baseline = OCRTextMetrics(lines: ["2026.12.31", "2026.12.31", "1234 5678 9012"])

      let same = OCRTextMetrics(lines: ["2026.12.31 2026.12.31", "123456789012"])
      #expect(baseline.missingDates(in: same) == 0)
      #expect(baseline.missingLongNumbers(in: same) == 0)

      let misread = OCRTextMetrics(lines: ["2026.12.31", "2026.12.81", "1234 5678 9013"])
      #expect(baseline.missingDates(in: misread) == 1)
      #expect(baseline.missingLongNumbers(in: misread) == 1)
      #expect(baseline.missingDates(in: OCRTextMetrics(lines: [])) == 2)
    }
  }
#endif
