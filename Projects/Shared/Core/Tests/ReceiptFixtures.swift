import Core
import CoreGraphics
import Foundation
import Testing

// 영수증 추출·목록 테스트가 함께 쓰는 값. OCR 줄·가게 이름은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).

/// 영수증 OCR 줄 하나. 좌표는 0~1 정규화, 원점은 왼쪽 위.
func receiptLine(
  _ text: String,
  x: CGFloat = 0.1,
  y: CGFloat,
  width: CGFloat = 0.6,
  height: CGFloat = 0.03
) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y, width: width, height: height))
}

/// 위에서 아래로 겹치지 않게 쌓은 줄(줄 간격이 라벨 높이의 1.5배를 넘지 않아 바로 아래 줄로 읽힌다).
func stackedReceiptLines(_ texts: [String]) -> [RecognizedTextLine] {
  texts.enumerated().map { index, text in receiptLine(text, y: 0.1 + CGFloat(index) * 0.04) }
}

func extractReceipt(_ texts: [String]) -> ReceiptInfo {
  ReceiptExtractor.extract(from: stackedReceiptLines(texts))
}

/// 금액. 테스트 실수(음수·상한 초과)면 멈춘다.
func receiptAmount(_ minorUnits: Int, _ currency: ReceiptCurrency) -> ReceiptAmount {
  ReceiptAmount(minorUnits: minorUnits, currency: currency)!
}

/// 추출 경로 하나: 줄과 기대 값. 테스트 이름에 경로 번호를 보인다.
struct ReceiptPath: Sendable, CustomTestStringConvertible {
  let name: String
  let lines: [RecognizedTextLine]
  let amount: ReceiptAmount?
  let storeName: String?
  let isCancelled: Bool

  init(
    _ name: String,
    _ texts: [String],
    amount: ReceiptAmount? = nil,
    storeName: String? = nil,
    isCancelled: Bool = false
  ) {
    self.init(name, lines: stackedReceiptLines(texts), amount: amount, storeName: storeName, isCancelled: isCancelled)
  }

  init(
    _ name: String,
    lines: [RecognizedTextLine],
    amount: ReceiptAmount? = nil,
    storeName: String? = nil,
    isCancelled: Bool = false
  ) {
    self.name = name
    self.lines = lines
    self.amount = amount
    self.storeName = storeName
    self.isCancelled = isCancelled
  }

  var testDescription: String { self.name }

  var extracted: ReceiptInfo { ReceiptExtractor.extract(from: self.lines) }
}

/// 생성일을 ISO 8601 문자열로 적은 영수증 이미지 메타데이터.
func receiptAsset(_ id: String, created: String? = nil) -> ImageAsset {
  ImageAsset(
    id: id,
    creationDate: created.map { ISO8601DateFormatter().date(from: $0)! },
    coordinate: nil,
    pixelWidth: 1170,
    pixelHeight: 2532,
    isScreenshot: false
  )
}

/// 추출한 영수증 항목.
func extractedReceipt(
  _ id: String,
  created: String? = nil,
  store: String? = "예시마트",
  amount: ReceiptAmount? = nil,
  isCancelled: Bool = false
) -> ReceiptListItem {
  ReceiptListItem(
    asset: receiptAsset(id, created: created),
    status: .extracted(ReceiptInfo(storeName: store, amount: amount, isCancelled: isCancelled))
  )
}

/// 추출 전 항목.
func checkingReceipt(_ id: String, created: String? = nil) -> ReceiptListItem {
  ReceiptListItem(asset: receiptAsset(id, created: created), status: .checking)
}
