import Core
import Foundation
import Testing

struct ReceiptInfoTests {
  @Test(
    "가게 키는 소문자·공백·(주)·㈜·주식회사·株式会社·문장 부호를 지우고 지점 이름은 남긴다",
    arguments: [
      ("스타벅스 강남점", "스타벅스강남점"),
      ("(주)예시상사", "예시상사"),
      ("㈜예시상사", "예시상사"),
      ("주식회사 예시상사", "예시상사"),
      ("예시상사(주)", "예시상사"),
      ("株式会社ローソン", "ローソン"),
      ("Example Co., Ltd.", "example"),
      ("Example Inc.", "example"),
      ("(주) 예시상사", "예시상사"),
      ("예시상사 (주)", "예시상사"),
      ("Zinc.Cafe", "zinccafe"),
      ("NOODLES & CO", "noodlesco"),
      ("Trader Joe's", "traderjoes"),
    ]
  )
  func normalizesStoreKey(_ name: String, _ key: String) {
    #expect(ReceiptExtractor.storeKey(name) == key)
  }

  @Test("지점이 다르면 가게 키가 다르다")
  func branchesStaySeparate() {
    #expect(ReceiptExtractor.storeKey("스타벅스 강남점") != ReceiptExtractor.storeKey("스타벅스 역삼점"))
    #expect(ReceiptExtractor.storeKey("(주)예시마트") == ReceiptExtractor.storeKey("예시마트"))
  }

  @Test("글자·숫자가 남지 않으면 가게 키가 없고, 빈 가게 이름은 nil 로 둔다")
  func emptyKeysAndNames() {
    #expect(ReceiptExtractor.storeKey("(주)") == nil)
    #expect(ReceiptExtractor.storeKey(" - · ") == nil)
    #expect(ReceiptInfo(storeName: "  ", amount: nil, isCancelled: false).storeName == nil)
    #expect(ReceiptInfo(storeName: " 예시마트 ", amount: nil, isCancelled: false).storeName == "예시마트")
    #expect(ReceiptInfo(storeName: nil, amount: nil, isCancelled: false).storeKey == nil)
    #expect(ReceiptInfo(storeName: "(주)", amount: nil, isCancelled: false).storeKey == nil)
    #expect(ReceiptInfo.empty == ReceiptInfo(storeName: nil, amount: nil, isCancelled: false))
  }

  @Test("금액은 음수·상한 초과로 만들 수 없고, 최소 단위를 정확한 Decimal 로 바꾼다(KRW 0자리·USD 2자리)")
  func amountBoundsAndValue() {
    #expect(ReceiptAmount(minorUnits: -1, currency: .krw) == nil)
    #expect(ReceiptAmount(minorUnits: ReceiptAmount.maximumMinorUnits + 1, currency: .krw) == nil)
    #expect(ReceiptAmount(minorUnits: ReceiptAmount.maximumMinorUnits, currency: .usd) != nil)
    #expect(ReceiptAmount(minorUnits: 0, currency: .jpy)?.value == 0)
    #expect(receiptAmount(9000, .krw).value == Decimal(9000))
    #expect(receiptAmount(4520, .usd).value == Decimal(string: "45.20"))
    #expect(receiptAmount(1234, .jpy).value == Decimal(1234))
    #expect(receiptAmount(8801, .cny).value == Decimal(string: "88.01"))
    #expect(ReceiptCurrency.allCases.map(\.minorUnitDigits) == [0, 2, 0, 2, 2])
  }
}
