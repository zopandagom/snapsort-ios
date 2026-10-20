import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 기프티콘 추출 값의 언어 모델 보강 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStore {
  func gifticonModelFillPendingIDs() throws -> Set<ImageAsset.ID> {
    let rawValue = ImageCategory.gifticon.rawValue
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.textLinesData != nil && image.memberships.contains { $0.category == rawValue }
      }
    )
    descriptor.propertiesToFetch = [
      \.assetID, \.gifticonRulesVersion, \.gifticonExpiryDay, \.gifticonModelVersion, \.gifticonModelFailures,
    ]
    // 추출 대기처럼 만료일 해석(`storedGifticon`)을 조건으로 쓸 수 없어 여기서 거른다. 후보는 기프티콘 읽음 행뿐이다.
    return try Set(
      self.modelContext.fetch(descriptor).filter(Self.isExtractedAndNotFilled).map(\.assetID)
    )
  }

  func saveGifticonModelFills(_ results: [ImageAsset.ID: GifticonModelFillResult]) throws {
    try self.write {
      let ids = Array(results.keys)
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      for image in stored {
        // 보강 대기 행만 바꾼다. 겹친 지난 실행이 마친 행을 덮지 않고, 규칙으로 다시 추출해야 하는 행
        // (추출 대기)에 옛 줄로 계산한 값이 붙지 않는다.
        guard Self.isModelFillPending(image), let result = results[image.assetID] else {
          continue
        }
        // 다른 보강 버전에서 센 실패 수는 없으므로 0 에서 센다.
        let failures = if case let .pending(failures) = Self.modelFill(image) {
          failures
        } else {
          0
        }
        switch result {
        case let .filled(gifticon):
          Self.setGifticon(gifticon, on: image)
          Self.setModelFill(.done, on: image)
        case let .failed(rules):
          Self.setGifticon(rules, on: image)
          Self.setModelFill(
            failures + 1 >= GifticonModelFill.maximumFailures ? .done : .pending(failures: failures + 1),
            on: image
          )
        case let .deferred(rules):
          Self.setGifticon(rules, on: image)
          Self.setModelFill(.pending(failures: failures), on: image)
        }
      }
    }
  }

  /// 보강 상태를 `StoredImage.gifticonModelVersion`·`gifticonModelFailures` 로 읽는다. 지금 보강 버전이면 마침,
  /// 0 이면 보강하지 않음(실패 수와 함께), 그 밖(앱을 되돌려 남은 더 높은 버전 포함)은 다른 보강 버전이다.
  /// 두 값이 다 있어도 마친 것으로 보지 않는다(`IndexedImage.gifticonModelFill`).
  static func modelFill(_ stored: StoredImage) -> GifticonModelFill {
    switch stored.gifticonModelVersion {
    case GifticonExtractor.modelFillVersion:
      .done
    case 0:
      .pending(failures: stored.gifticonModelFailures)
    default:
      .stale
    }
  }

  /// 마침이면 (지금 버전, 0), 보강하지 않음이면 (0, 실패 수) 를 쓴다. 다른 보강 버전은 쓰는 경로가 없어(인덱서는 읽은 값을
  /// 되돌려 쓰지 않는다) 보강하지 않음 (0, 0) 으로 쓴다.
  static func setModelFill(_ fill: GifticonModelFill, on stored: StoredImage) {
    switch fill {
    case .done:
      stored.gifticonModelVersion = GifticonExtractor.modelFillVersion
      stored.gifticonModelFailures = 0
    case let .pending(failures):
      stored.gifticonModelVersion = 0
      stored.gifticonModelFailures = failures
    case .stale:
      stored.gifticonModelVersion = 0
      stored.gifticonModelFailures = 0
    }
  }

  /// 기프티콘으로 분류돼 글자를 읽었고 지금 규칙 버전으로 추출했는데(추출 대기가 아님) 보강을 마치지 않았다.
  private static func isModelFillPending(_ stored: StoredImage) -> Bool {
    let rawValue = ImageCategory.gifticon.rawValue
    return stored.textLinesData != nil
      && stored.memberships.contains { $0.category == rawValue }
      && Self.isExtractedAndNotFilled(stored)
  }

  /// 보강 대기 조건 중 추출 값·보강 상태 부분. 조회는 나머지를 조건으로 넣으므로 OCR 줄을 읽지 않고 이것만 본다.
  private static func isExtractedAndNotFilled(_ stored: StoredImage) -> Bool {
    storedGifticon(stored) != nil && self.modelFill(stored) != .done
  }
}
