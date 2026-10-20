import Foundation

/// 캡처 이미지에서 읽은, 바로 행동할 수 있는 값. 찾지 못하면 빈 배열이다.
public struct CaptureInfo: Sendable, Hashable {
  /// 주소. 지도 앱 열기에 쓴다.
  public let addresses: [CapturedText]
  /// 택배 송장번호. 복사에 쓴다.
  public let trackingNumbers: [CapturedText]
  /// 은행 계좌번호. 복사에 쓴다.
  public let accountNumbers: [CapturedText]

  public init(addresses: [CapturedText], trackingNumbers: [CapturedText], accountNumbers: [CapturedText]) {
    self.addresses = addresses
    self.trackingNumbers = trackingNumbers
    self.accountNumbers = accountNumbers
  }
}

/// OCR 줄에서 찾은 값 하나.
public struct CapturedText: Sendable, Hashable {
  /// 원문 그대로의 값(번호의 하이픈 포함).
  public let text: String
  /// 값을 찾은 줄의 순서(입력 배열의 인덱스). 화면이 이미지 위 위치를 보일 때 쓴다.
  public let lineIndex: Int

  public init(text: String, lineIndex: Int) {
    self.text = text
    self.lineIndex = lineIndex
  }
}

/// 저장된 OCR 줄에서 주소·송장번호·계좌번호를 찾는 규칙 (docs/ARCHITECTURE.md §4 캡처 정보 추출).
/// 결과를 저장하지 않고 화면이 필요할 때 부르므로, 규칙을 바꿔도 다시 추출할 저장 행이 없다(버전을 두지 않는다).
/// 주소는 줄마다 찾는다. 한글이 있는 줄은 한국 주소 규칙(`CaptureInfoExtractor+KoreanAddress.swift`)으로, 없는 줄은 Foundation 의 주소 감지
/// (`NSDataDetector`, 기기 안에서만 동작)로 찾는다. 주소 감지는 기기 환경에 따라 한국어 주소를 하나도 찾지 못해서
/// (CI 의 iOS 26.5 시뮬레이터에서 확인) 한국어 줄은 환경과 상관없이 같은 결과를 내는 규칙만 쓴다.
/// 번호는 키워드(택배사·"송장", 은행·"계좌")가 있는 줄의 번호, 그 줄에 숫자가 없으면 바로 다음 줄이 번호로 시작할 때 그 번호를 쓴다.
/// 키워드는 OCR 이 "운 송 장"처럼 띄워 읽어도 찾도록 공백을 무시하고 소문자로 대조한다.
/// 키워드는 `ClassificationRules` 키워드 표와 따로 둔다(`scripts/mask-samples.py` 는 그 표만 읽는다).
/// 결과에 사진에서 읽은 텍스트가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public enum CaptureInfoExtractor {
  /// 송장번호 키워드. 공백 없이 소문자로 적는다. 한 줄에 계좌 키워드와 함께 있으면 계좌로 본다("택배비 송금 신한은행").
  /// 단 함께 있는 계좌 키워드가 택배사 이름이기도 한 것(`trackingAccountKeywords`, "우체국택배")뿐이면 송장으로 본다.
  static let trackingKeywords = ["운송장", "송장", "택배", "등기번호", "대한통운", "한진", "로젠", "tracking"]
  /// 계좌번호 키워드. 공백 없이 소문자로 적는다. "은행"·"뱅크"가 은행 이름 대부분("국민은행"·"카카오뱅크")을 덮는다.
  static let accountKeywords = ["계좌", "입금", "은행", "뱅크", "농협", "신협", "새마을금고", "우체국", "kb국민", "sc제일"]
  /// 택배사 이름이기도 한 계좌 키워드. 송장 키워드와 함께 있을 때 이것만 있으면 송장으로 본다.
  static let trackingAccountKeywords: Set = ["우체국"]
  /// 송장·계좌번호로 보는 숫자 개수 범위. 국내 택배 송장(10~13자리)과 은행 계좌(10~14자리)를 덮고,
  /// 날짜("2026-12-31", 8자리)와 대표번호("1588-1234", 8자리)는 빠진다.
  static let numberDigitRange = 10 ... 14

  /// 하이픈으로 이어진 숫자 묶음. 공백으로 나뉜 숫자는 잇지 않는다(다른 숫자와 붙어 자릿수가 틀어진다).
  private static var numberPattern: Regex<Substring> { #/[0-9]+(?:-[0-9]+)*/# }

  public static func extract(from textLines: [RecognizedTextLine]) -> CaptureInfo {
    let texts = textLines.map(\.text)
    var trackingNumbers: [CapturedText] = []
    var accountNumbers: [CapturedText] = []
    for (index, text) in texts.enumerated() {
      let normalized = Self.normalizedForKeywords(text)
      let accountKeywords = Set(Self.accountKeywords.filter { normalized.contains($0) })
      let isTracking = Self.trackingKeywords.contains { normalized.contains($0) }
        && accountKeywords.isSubset(of: Self.trackingAccountKeywords)
      guard isTracking || !accountKeywords.isEmpty else { continue }
      let found = Self.numbers(onKeywordLineAt: index, in: texts)
      if isTracking {
        trackingNumbers += found
      } else {
        accountNumbers += found
      }
    }
    return CaptureInfo(
      addresses: Self.unique(Self.addresses(in: texts)) { $0.text },
      trackingNumbers: Self.unique(trackingNumbers) { Self.digits($0.text) },
      accountNumbers: Self.unique(accountNumbers) { Self.digits($0.text) }
    )
  }

  /// 줄마다 찾은 주소. 여러 줄에 걸친 주소는 줄마다 찾은 부분만 찾는다.
  private static func addresses(in texts: [String]) -> [CapturedText] {
    // `NSDataDetector` 는 Sendable 이 아니어서 정적 프로퍼티로 두지 않고 부를 때마다 만든다. 주소 타입만으로 만들면 실패하지 않는다.
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    return texts.enumerated().flatMap { index, text in
      let found = text.contains(where: \.isHangul)
        ? Self.koreanAddresses(in: text)
        : (detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).compactMap {
          Range($0.range, in: text).map { String(text[$0]) }
        }
      return found.map { CapturedText(text: $0, lineIndex: index) }
    }
  }

  /// 키워드 줄의 번호. 그 줄에 숫자 묶음이 하나도 없으면 바로 다음 줄이 번호로 시작할 때 그 줄의 번호(라벨 아래에 값을 적는 배치).
  /// 키워드 줄에 숫자가 있는데 번호가 아니면(전화번호·날짜) 그 숫자가 키워드의 값이므로 다음 줄을 보지 않는다.
  /// 영문자와 붙은 숫자는 이름의 일부("GS25 반값택배")라 다음 줄을 막지 않는다.
  private static func numbers(onKeywordLineAt index: Int, in texts: [String]) -> [CapturedText] {
    let onLine = Self.numbers(in: texts[index]).map { CapturedText(text: $0, lineIndex: index) }
    guard onLine.isEmpty,
          Self.numberGroups(in: texts[index]).isEmpty,
          texts.indices.contains(index + 1)
    else { return onLine }
    let next = texts[index + 1]
    guard next.first?.isASCIIDigit == true else { return [] }
    return Self.numbers(in: next).map { CapturedText(text: $0, lineIndex: index + 1) }
  }

  /// 한 줄에서 송장·계좌번호로 볼 수 있는 숫자 묶음. 전화번호와 범위 밖 자릿수는 뺀다.
  /// 국제 표기 전화번호는 "+" 바로 뒤의 묶음("+82-10-1234-5678")이거나, 앞부분이 공백·괄호를 빼고 "+82"(뒤에 "(0)" 이 붙은 것 포함)로
  /// 끝나는 묶음("+82 10-1234-5678", "(+82) 10-1234-5678", "+82 (0)10-1234-5678")이라 뺀다.
  static func numbers(in text: String) -> [String] {
    self.numberGroups(in: text).compactMap { match in
      let before = text[..<match.range.lowerBound]
      let prefix = before.filter { !$0.isWhitespace && $0 != "(" && $0 != ")" }
      let isInternationalPhone = before.last == "+" || prefix.hasSuffix("+82") || prefix.hasSuffix("+820")
      let number = String(match.output)
      guard !isInternationalPhone,
            Self.numberDigitRange.contains(Self.digits(number).count),
            !Self.isPhoneNumber(number)
      else { return nil }
      return number
    }
  }

  /// 한 줄의 숫자 묶음 중 영문자와 붙지 않은 것. 영문자와 붙은 묶음은 주문번호("A1234567890")나 이름("GS25")의 일부다.
  private static func numberGroups(in text: String) -> [Regex<Substring>.Match] {
    text.matches(of: self.numberPattern).filter { match in
      ![
        match.range.lowerBound > text.startIndex ? text[text.index(before: match.range.lowerBound)] : nil,
        match.range.upperBound < text.endIndex ? text[match.range.upperBound] : nil,
      ].contains { $0?.isASCIILetter == true }
    }
  }

  /// 0 으로 시작하는 전화번호 모양: "010-1234-5678"·"02-123-4567" 처럼 2~3·3~4·4자리 세 묶음, 또는 하이픈 없는 10~11자리.
  /// 택배·배달 화면의 안심번호(050X)는 "0504-1234-5678" 처럼 4·3~4·4자리 세 묶음, 또는 하이픈 없는 11~12자리다.
  /// 네 묶음("010-1234-5678-09", 휴대폰 번호 계좌)은 계좌로 둔다.
  static func isPhoneNumber(_ number: String) -> Bool {
    guard number.hasPrefix("0") else { return false }
    let groups = number.split(separator: "-").map(\.count)
    let isSafeNumber = number.hasPrefix("050")
    switch groups.count {
    case 1:
      return isSafeNumber ? (11 ... 12).contains(groups[0]) : (10 ... 11).contains(groups[0])
    case 3:
      return (isSafeNumber ? groups[0] == 4 : (2 ... 3).contains(groups[0]))
        && (3 ... 4).contains(groups[1]) && groups[2] == 4
    default:
      return false
    }
  }

  private static func normalizedForKeywords(_ text: String) -> String {
    text.filter { !$0.isWhitespace }.lowercased()
  }

  private static func digits(_ text: String) -> String {
    text.filter(\.isASCIIDigit)
  }

  /// 같은 값이 여러 줄에 있으면(같은 송장번호를 두 번 적은 화면) 처음 것만 둔다.
  private static func unique(_ values: [CapturedText], _ key: (CapturedText) -> String) -> [CapturedText] {
    var seen: Set<String> = []
    return values.filter { seen.insert(key($0)).inserted }
  }
}

extension Character {
  var isASCIIDigit: Bool {
    self.isASCII && self.isNumber
  }

  var isASCIILetter: Bool {
    self.isASCII && self.isLetter
  }

  /// 한글 음절("가"~"힣").
  var isHangul: Bool {
    self.unicodeScalars.allSatisfy { (0xAC00 ... 0xD7A3).contains($0.value) }
  }
}
