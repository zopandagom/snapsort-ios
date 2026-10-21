import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 영수증 추출 값과 영수증 목록 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStore {
  func receiptExtractionPendingIDs() throws -> Set<ImageAsset.ID> {
    let rawValue = ImageCategory.receipt.rawValue
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.textLinesData != nil && image.memberships.contains { $0.category == rawValue }
      }
    )
    descriptor.propertiesToFetch = [
      \.assetID, \.receiptRulesVersion, \.receiptAmountMinorUnits, \.receiptCurrencyCode,
    ]
    // 버전 비교를 조건에 넣지 않고 여기서 거르는 것은 기프티콘과 같이 해석 불가 판정(`storedReceipt`)을 조건으로 쓸 수 없어서다.
    return try Set(
      self.modelContext.fetch(descriptor).filter { Self.storedReceipt($0) == nil }.map(\.assetID)
    )
  }

  func saveReceipts(_ receipts: [ImageAsset.ID: ReceiptInfo]) throws {
    try self.write {
      let ids = Array(receipts.keys)
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      let rawValue = ImageCategory.receipt.rawValue
      for image in stored {
        // `receiptExtractionPendingIDs` 와 같은 조건인 행만 바꾼다. 겹친 지난 실행이 새 값을 덮거나,
        // 영수증에서 빠졌다 다시 대기가 된 행에 지난 값이 붙지 않는다.
        guard image.textLinesData != nil,
              image.memberships.contains(where: { $0.category == rawValue }),
              Self.storedReceipt(image) == nil,
              let receipt = receipts[image.assetID]
        else {
          continue
        }
        Self.setReceipt(receipt, on: image)
      }
    }
  }

  func receipts() throws -> [ReceiptListItem] {
    let rawValue = ImageCategory.receipt.rawValue
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.memberships.contains { $0.category == rawValue }
        }
      )
    )
    return stored.sorted(by: Self.isNewer).map(Self.receiptListItem)
  }

  /// 저장된 영수증 추출 값. nil 이면 추출하지 않은 것으로 본다(읽기·추출 대기·`saveReceipts`·목록이 모두 이 판정을 쓴다).
  /// 버전은 맞는데 금액·통화를 해석하지 못하면(한쪽만 있음, 모르는 통화 코드, 음수, 상한 초과) 던지지 않고 추출하지 않은 것으로 본다.
  /// 던지면 그 행이 든 `receipts()`·`images(in: .receipt)` 가 계속 실패해 사용자가 회복할 수 없고, 값은 저장된 줄로 다시 만들 수 있다
  /// (추출 대기에 들어 영수증 소급 추출이 다시 쓴다). 쓰는 쪽은 늘 유효한 값을 쓰므로 정상 흐름에서는 생기지 않는다.
  static func storedReceipt(_ stored: StoredImage) -> ReceiptInfo? {
    // `!=` 라 앱을 되돌려 더 높은 버전이 남아도 다시 추출한다.
    guard stored.receiptRulesVersion == ReceiptExtractor.rulesVersion else {
      return nil
    }
    let amount: ReceiptAmount?
    switch (stored.receiptAmountMinorUnits, stored.receiptCurrencyCode) {
    case (nil, nil):
      amount = nil
    case let (minorUnits?, code?):
      guard let currency = ReceiptCurrency(rawValue: code),
            let value = ReceiptAmount(minorUnits: minorUnits, currency: currency)
      else {
        return nil
      }
      amount = value
    default:
      return nil
    }
    return ReceiptInfo(storeName: stored.receiptStoreName, amount: amount, isCancelled: stored.receiptIsCancelled)
  }

  /// 추출함이면 지금 규칙 버전과 값을, nil(추출 안 함)이면 (0, nil, nil, nil, false) 를 쓴다.
  static func setReceipt(_ receipt: ReceiptInfo?, on stored: StoredImage) {
    stored.receiptRulesVersion = receipt == nil ? 0 : ReceiptExtractor.rulesVersion
    stored.receiptStoreName = receipt?.storeName
    stored.receiptAmountMinorUnits = receipt?.amount?.minorUnits
    stored.receiptCurrencyCode = receipt?.amount?.currency.rawValue
    stored.receiptIsCancelled = receipt?.isCancelled ?? false
  }

  /// 영수증 카테고리 행의 목록 항목. 줄을 디코딩하지 않고 OCR 상태는 `needsTextRecognition`·`textLinesData` 유무로 본다.
  /// 추출 값이 있으면 `.extracted`, 없고 OCR 대기·추출 대기면 `.checking`, OCR 대상이 아니면 찾을 값이 없어 빈 추출 값이다.
  private static func receiptListItem(_ stored: StoredImage) -> ReceiptListItem {
    let status: ReceiptListItem.Status = if let receipt = Self.storedReceipt(stored) {
      .extracted(receipt)
    } else if stored.needsTextRecognition || stored.textLinesData != nil {
      .checking
    } else {
      .extracted(.empty)
    }
    return ReceiptListItem(asset: Self.imageAsset(stored), status: status)
  }
}
