// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import CoreGraphics
  import Foundation

  /// OCR 해상도 비교에서 기준(현재 원본 상한 `.largestAvailable`)과 견줄 낮은 픽셀 수 상한.
  struct OCRResolutionCap: Sendable, Equatable {
    let name: String
    let maxPixelCount: Int

    /// 비교할 상한(4:3 기준 크기). 이 목록만 바꾸면 측정·요약·화면·측정 파일이 따른다.
    static let all = [
      OCRResolutionCap(name: "8MP", maxPixelCount: 3264 * 2448),
      OCRResolutionCap(name: "4MP", maxPixelCount: 2304 * 1728),
      OCRResolutionCap(name: "2MP", maxPixelCount: 1632 * 1224),
      OCRResolutionCap(name: "1MP", maxPixelCount: 1152 * 864),
    ]
  }

  /// OCR 해상도 비교의 입력 만들기와 순서. 모두 부수효과 없는 함수다.
  enum OCRResolution {
    /// 측정 파일에 남기는 회전 규칙 설명.
    static let rotationDescription = "index % variantCount 만큼 [baseline, caps…] 를 왼쪽으로 회전"

    /// 픽셀 수가 `maxPixelCount` 이하가 되게 비율을 지켜 줄인 크기. 이미 이하면 nil(같은 입력).
    /// 긴 변은 PhotoLibrary Impl `ImageLoader.maxPixelLength(width:height:maxPixelCount:)` 와 같은 식이다. 한쪽 식을 바꾸면 다른 쪽도 맞춘다.
    /// 짧은 변은 운영에서 ImageIO 가 정하므로 비율로 반올림한 근사다(1px 정도 다를 수 있다).
    static func downscaledSize(width: Int, height: Int, maxPixelCount: Int) -> (width: Int, height: Int)? {
      let pixelCount = width * height
      guard pixelCount > maxPixelCount else { return nil }
      let longSide = CGFloat(max(width, height))
      let shortSide = CGFloat(min(width, height))
      let newLong = (longSide * (CGFloat(maxPixelCount) / CGFloat(pixelCount)).squareRoot()).rounded(.down)
      let newShort = max(1, (shortSide * newLong / longSide).rounded())
      return width >= height ? (Int(newLong), Int(newShort)) : (Int(newShort), Int(newLong))
    }

    /// 기준 이미지를 `size` 로 줄인다. 8bit RGBA 비트맵에 `.high` 보간으로 그리고, 색 공간은 기준이 RGB 면 그대로, 아니면 sRGB 다.
    /// 기준 색 공간으로 8bit 비트맵을 만들 수 없으면(확장 범위 색 공간 등) sRGB 로 한 번 더 시도한다. 그래도 못 만들면 nil.
    /// 방향은 기준 그대로 두고 대체 버전 표시는 없다(대체 버전 기준은 비교하지 않는다).
    static func downscale(_ image: AnalysisImage, to size: (width: Int, height: Int)) -> AnalysisImage? {
      let source = image.cgImage
      let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
      let sourceSpace = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
      let spaces = [sourceSpace, sRGB].compactMap(\.self)
      for space in spaces {
        guard
          let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
        else { continue }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { return nil }
        return AnalysisImage(cgImage: scaled, orientation: image.orientation)
      }
      return nil
    }

    /// 이미지 한 장의 OCR 순서. 변형 목록 `[기준, 상한…]` 의 위치(0 = 기준)를 처리 순서 `index` 만큼 왼쪽으로 돌린 순서로 준다.
    /// 기준도 회전에 넣어 "기준이 늘 먼저(덜 뜨거움)" 편향을 없앤다.
    static func variantOrder(index: Int, variantCount: Int) -> [Int] {
      guard variantCount > 0 else { return [] }
      let shift = index % variantCount
      return (0 ..< variantCount).map { ($0 + shift) % variantCount }
    }
  }

  /// OCR 줄에서 뽑은 비교용 값. 메모리 안에서만 쓰고 기록에는 개수만 남긴다.
  struct OCRTextMetrics: Equatable {
    /// 정규화(NFC → 소문자 → 공백 제거)한 글자의 다중집합.
    let charCounts: [Character: Int]
    let charCount: Int
    /// 날짜 값의 다중집합. 값은 찾은 날짜에서 공백만 지운 문자열이다(`Self.dates(in:)`).
    let dates: [String: Int]
    /// 10자리 이상 숫자열의 다중집합. 값은 이어 붙인 숫자다(`Self.longNumbers(in:)`).
    let longNumbers: [String: Int]

    /// 세 지표 모두 줄마다 NFC 로 맞춘 같은 텍스트에서 찾는다. 공백은 숫자 토큰의 경계라 지우지 않고 찾는다.
    init(lines: [String]) {
      let datePattern = Self.datePattern
      var charCounts: [Character: Int] = [:]
      var dates: [String: Int] = [:]
      var longNumbers: [String: Int] = [:]
      for line in lines {
        let text = line.precomposedStringWithCanonicalMapping
        for character in text.lowercased() where !character.isWhitespace {
          charCounts[character, default: 0] += 1
        }
        let (found, rest) = Self.dates(in: text, pattern: datePattern)
        for date in found {
          dates[date, default: 0] += 1
        }
        for number in Self.longNumbers(in: rest) {
          longNumbers[number, default: 0] += 1
        }
      }
      self.charCounts = charCounts
      self.charCount = charCounts.values.reduce(0, +)
      self.dates = dates
      self.longNumbers = longNumbers
    }

    var dateCount: Int {
      self.dates.values.reduce(0, +)
    }

    var longNumberCount: Int {
      self.longNumbers.values.reduce(0, +)
    }

    /// 이 값(기준)의 글자 중 `variant` 에도 있는 수: `Σ_c min(기준[c], 변형[c])`. 순서·줄 나눔에 둔감하고, 잘못 읽은 글자는 빠진 것으로 센다.
    func matchedCharCount(in variant: OCRTextMetrics) -> Int {
      self.charCounts.reduce(0) { $0 + min($1.value, variant.charCounts[$1.key] ?? 0) }
    }

    /// 이 값(기준)의 날짜 중 `variant` 에 없는 수(다중집합 차). 한 자리만 잘못 읽어도 놓친 것으로 센다.
    func missingDates(in variant: OCRTextMetrics) -> Int {
      Self.missingCount(self.dates, in: variant.dates)
    }

    /// 이 값(기준)의 긴 숫자열 중 `variant` 에 없는 수(다중집합 차).
    func missingLongNumbers(in variant: OCRTextMetrics) -> Int {
      Self.missingCount(self.longNumbers, in: variant.longNumbers)
    }

    /// 만료일·결제일 형식: 구분자(`.`·`/`·`-`, 앞뒤 공백 허용) 날짜, `년월일` 날짜, 압축 날짜(`20261231`).
    /// 월 1~12·일 1~31(한 자리·0 패딩 모두), 4자리 연도는 19xx·20xx 만 날짜다(`12-34-56-78-90`·`3000-10-20` 은 아니다).
    /// "12/31" 같은 연도 없는 형식은 오탐이 많아 뺀다. 일 뒤에 숫자가 바로 이어지면 날짜로 보지 않는다
    /// (`123-45-67890` 의 `23-45-67`, 공백을 빠뜨려 시각과 붙은 `2026.1.510:30`). 숫자는 ASCII 만 본다(`isDigit` 과 같다).
    /// 한계: 범위 안에 드는 버전 번호(`iOS 26.6.2`)·IP 조각과 구분자가 섞인 `2026.12-31` 은 날짜로 센다(구분할 수 없고 기준·변형에 같은 규칙).
    /// `Regex` 가 `Sendable` 이 아니어서 계산 프로퍼티로 두고, 쓰는 쪽은 한 번 만들어 재사용한다.
    private static var datePattern: Regex<Substring> {
      // 여러 줄 리터럴은 확장 문법이라 패턴 안의 공백·줄바꿈을 무시한다.
      #/
        (?:(?:19|20)\d{2}|\d{2})\s*[./-]\s*(?:0?[1-9]|1[0-2])\s*[./-]\s*(?:0?[1-9]|[12]\d|3[01])(?!\d)
        | (?:19|20)\d{2}\s*년\s*(?:0?[1-9]|1[0-2])\s*월\s*(?:0?[1-9]|[12]\d|3[01])\s*일
        | (?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?!\d)
      /#
      .asciiOnlyDigits()
    }

    /// 줄에서 날짜를 찾아 값(공백을 지운 매치)과, 날짜 자리를 `|` 로 바꾼 나머지 텍스트를 준다.
    /// 날짜 숫자가 숫자열에 섞이지 않게 하려는 것이고, `|` 는 연결자가 아니라 앞뒤 숫자도 이어지지 않는다.
    /// 매치 바로 앞이 숫자이거나 숫자 뒤의 `.`·`/`·`-` 면 더 긴 번호의 일부라 버리고, 그 자리는 숫자열 찾기에 남긴다.
    /// 단, 그 숫자가 직전에 인정한 날짜의 마지막 글자면(공백 없는 기간 `2026.01.01-2026.12.31`) 번호의 일부로 보지 않는다.
    /// 한계: 매치는 겹치지 않게 훑으므로 버린 매치가 그 안에서 시작하는 다른 날짜를 가릴 수 있다(드물고 기준·변형에 같은 규칙).
    /// 8자리 번호가 우연히 날짜 형식이면 날짜로 센다(10자리 미만이라 숫자열이 아니고, 기준·변형에 같은 규칙).
    static func dates(in text: String, pattern: Regex<Substring>) -> (dates: [String], rest: String) {
      var dates: [String] = []
      var rest = ""
      var cursor = text.startIndex
      // 직전에 인정한 날짜의 마지막 글자. 버린 매치는 옮기지 않는다.
      var lastDateCharacter: String.Index?
      for match in text.matches(of: pattern) {
        guard !self.followsNumber(match.range.lowerBound, in: text, except: lastDateCharacter) else { continue }
        dates.append(String(match.output.filter { !$0.isWhitespace }))
        rest += text[cursor ..< match.range.lowerBound]
        rest += "|"
        cursor = match.range.upperBound
        lastDateCharacter = text.index(before: cursor)
      }
      rest += text[cursor...]
      return (dates, rest)
    }

    /// 쿠폰·바코드·승인번호 후보: 숫자 덩어리를 연결자로 이은 사슬의 숫자가 10자리 이상이면 긴 숫자열이다.
    /// - 연결자는 공백형(공백만 1개 이상)과 하이픈형(`-` 하나, 앞뒤 공백 허용)이고, 한 사슬은 첫 연결자의 종류만 쓴다.
    ///   다른 종류나 그 밖의 틈(`,`·`:`·글자)이 오면 끊고, 다음 덩어리가 새 사슬을 시작한다(`02-123-4567 123-45-67890` → `1234567890`).
    /// - 덩어리 길이로는 끊지 않는다. 낮은 상한 OCR 이 공백 하나를 빠뜨린 `1234 56789012` 도 `1234 5678 9012` 와 같은 값이어야 한다.
    /// 한계: 같은 종류 연결자로 이어진 서로 다른 번호는 한 숫자열이 된다(기준·변형에 같은 규칙이라 놓친 수 비교는 일관된다).
    /// 하이픈을 공백으로 잘못 읽으면(`1234-5678 9012`) 사슬이 끊겨 놓친 것으로 센다(글자를 잘못 읽은 것이다).
    static func longNumbers(in text: String) -> [String] {
      var numbers: [String] = []
      var digits = ""
      var connector: Connector?
      var gap = ""
      func finish() {
        if digits.count >= 10 {
          numbers.append(digits)
        }
        digits = ""
        connector = nil
      }
      for character in text {
        guard Self.isDigit(character) else {
          gap.append(character)
          continue
        }
        if !gap.isEmpty, !digits.isEmpty {
          if let kind = Connector(gap: gap), connector == nil || connector == kind {
            connector = kind
          } else {
            finish()
          }
        }
        gap = ""
        digits.append(character)
      }
      finish()
      return numbers
    }

    /// 숫자 덩어리 사이의 틈 중 사슬을 잇는 것.
    enum Connector {
      case space
      case hyphen

      init?(gap: String) {
        if gap.allSatisfy(\.isWhitespace) {
          self = .space
        } else if gap.trimmingCharacters(in: .whitespaces) == "-" {
          self = .hyphen
        } else {
          return nil
        }
      }
    }

    private static func isDigit(_ character: Character) -> Bool {
      character.isASCII && character.isNumber
    }

    /// `index` 바로 앞이 숫자이거나, 숫자 뒤의 `.`·`/`·`-` 인지. 그 숫자가 `exception` 위치(직전 날짜의 끝)면 아니다.
    private static func followsNumber(_ index: String.Index, in text: String, except exception: String.Index?) -> Bool {
      guard index > text.startIndex else { return false }
      var numberIndex = text.index(before: index)
      if !self.isDigit(text[numberIndex]) {
        guard "./-".contains(text[numberIndex]), numberIndex > text.startIndex else { return false }
        numberIndex = text.index(before: numberIndex)
        guard self.isDigit(text[numberIndex]) else { return false }
      }
      return numberIndex != exception
    }

    private static func missingCount(_ baseline: [String: Int], in variant: [String: Int]) -> Int {
      baseline.reduce(0) { $0 + max(0, $1.value - (variant[$1.key] ?? 0)) }
    }
  }

  /// 이미지 한 장의 OCR 해상도 비교 기록. 텍스트·라벨·카테고리·날짜 값 없이 개수·크기·시간·불리언만 담는다.
  struct OCRComparisonRecord: Sendable, Equatable, Encodable {
    enum Status: String, Sendable, Encodable {
      /// 기준과 낮은 상한을 비교했다.
      case compared
      /// 원본이 iCloud 대체 버전이라 기준 OCR 만 하고 비교하지 않았다.
      case fallback
    }

    let status: Status
    /// 이 이미지에서 기준 OCR 의 순서(0부터).
    var baselineOrder: Int?
    var baselineCharCount: Int?
    var baselineDateCount: Int?
    var baselineLongNumberCount: Int?
    /// `OCRResolutionCap.all` 순서.
    var variants: [OCRVariantRecord] = []
  }

  /// 낮은 상한 하나의 결과. `sameInput`·`downscaleFailed` 는 OCR 하지 않아 지표가 없다.
  struct OCRVariantRecord: Sendable, Equatable, Encodable {
    enum Status: String, Sendable, Encodable {
      /// 줄여서 다시 OCR 했다.
      case downscaled
      /// 기준이 이미 상한 이하라 같은 입력이다. 다시 OCR 하지 않는다.
      case sameInput
      case downscaleFailed
      case ocrFailed
    }

    let cap: String
    var status: Status
    /// 이 이미지에서 이 변형 OCR 의 실제 순서(0부터). OCR 하지 않았으면 nil.
    var order: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?
    /// 변형 OCR 시간. 줄이기 시간은 운영에 없는 비용이라 재지 않는다.
    var ocrMs: Double?
    var textLineCount: Int?
    /// 기준 글자 중 이 변형에도 있는 수. 재현율은 이 값 ÷ `baselineCharCount` 다.
    var matchedCharCount: Int?
    /// 운영 라벨과 이 변형의 줄로 규칙 분류한 결과가 기준 줄의 결과와 같은지.
    var categoryMatches: Bool?
    var missingDateCount: Int?
    var missingLongNumberCount: Int?
  }
#endif
