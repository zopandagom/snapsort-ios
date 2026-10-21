import Foundation

/// 영수증 금액의 통화 (docs/ARCHITECTURE.md §4 영수증 추출). 지원하지 않는 통화는 "통화 모름"이라 금액을 정하지 않는다.
/// rawValue 는 ISO 4217 코드이고 저장 키이므로 바꾸지 않는다. 순서(`allCases`)는 합계 표시에서 같은 장수일 때의 순서다.
public enum ReceiptCurrency: String, Sendable, Hashable, CaseIterable {
  case krw = "KRW"
  case usd = "USD"
  case jpy = "JPY"
  case eur = "EUR"
  case cny = "CNY"

  /// 최소 단위 자릿수(ISO 4217). KRW·JPY 0, USD·EUR·CNY 2.
  public var minorUnitDigits: Int {
    switch self {
    case .krw, .jpy: 0
    case .usd, .eur, .cny: 2
    }
  }
}

/// 영수증 금액. 최소 단위 정수(KRW 원, USD 센트)와 통화. 늘 0 이상이다(취소는 `ReceiptInfo.isCancelled` 로 따로 둔다).
/// 사진에서 읽은 값이므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct ReceiptAmount: Sendable, Hashable {
  public let minorUnits: Int
  public let currency: ReceiptCurrency

  /// 이보다 크면 금액으로 보지 않는다(OCR 이 붙여 읽은 긴 숫자). 10^12 최소 단위(₩1조, $100억).
  public static let maximumMinorUnits = 1_000_000_000_000

  /// 음수이거나 상한을 넘으면 nil.
  public init?(minorUnits: Int, currency: ReceiptCurrency) {
    guard minorUnits >= 0, minorUnits <= Self.maximumMinorUnits else { return nil }
    self.minorUnits = minorUnits
    self.currency = currency
  }

  /// 정확한 10진 값(예: USD 4520 → 45.20).
  public var value: Decimal {
    Decimal(sign: .plus, exponent: -self.currency.minorUnitDigits, significand: Decimal(self.minorUnits))
  }
}

/// 영수증 이미지에서 읽은 정보 (docs/ARCHITECTURE.md §4 영수증 추출). 찾지 못한 값은 nil 이다.
/// 사진에서 읽은 텍스트(가게·금액)가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct ReceiptInfo: Sendable, Hashable {
  /// 가게 이름(OCR 텍스트 그대로, 앞뒤 공백만 뺀다). 못 찾았으면 nil. init 이 빈 문자열을 nil 로 둔다.
  public let storeName: String?
  /// 결제 금액. 못 찾음·통화 모름·해석 불가면 nil(화면 "금액 모름").
  public let amount: ReceiptAmount?
  /// 취소 전표. 합계에 넣지 않는다(차감하지 않고 뺀다). 금액 모름에도 세지 않는다.
  public let isCancelled: Bool

  public init(storeName: String?, amount: ReceiptAmount?, isCancelled: Bool) {
    let trimmed = storeName?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.storeName = trimmed?.isEmpty == false ? trimmed : nil
    self.amount = amount
    self.isCancelled = isCancelled
  }

  /// 가게별 묶음 키(`ReceiptExtractor.storeKey(_:)`). 가게 모름이거나 키가 비면 nil.
  public var storeKey: String? {
    self.storeName.flatMap(ReceiptExtractor.storeKey)
  }

  /// 찾을 값이 없는 빈 추출 값(글자를 읽지 않는 영수증).
  public static let empty = ReceiptInfo(storeName: nil, amount: nil, isCancelled: false)
}
