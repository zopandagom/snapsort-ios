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
      \.gifticonExpiryFromModel, \.gifticonRedemptionPlaceFromModel,
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
        // `.stale`·`.sourcesUnknown` 행은 센 실패 수가 없으므로 0 에서 센다.
        let fill = Self.modelFill(image)
        let failures = if case let .pending(failures) = fill {
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
        case let .resolvedSources(info):
          // 출처를 정하지 않은 행이고 저장된 두 값이 판정한 값과 같을 때만 출처를 쓴다. 그 사이 값이 바뀐 행에 옛 값으로 정한
          // 출처를 붙이지 않는다. 버전은 이미 지금 보강 버전이라 출처만 쓰면 다음 읽기부터 마침이다.
          guard fill == .sourcesUnknown, let stored = Self.storedGifticon(image),
                stored.expiryDate == info.expiryDate, stored.redemptionPlace == info.redemptionPlace
          else {
            continue
          }
          Self.setGifticon(info, on: image)
        }
      }
    }
  }

  /// 보강 상태를 `StoredImage.gifticonModelVersion`·`gifticonModelFailures` 로 읽는다. 지금 보강 버전이면 마침,
  /// 0 이면 보강하지 않음(실패 수와 함께), 그 밖(앱을 되돌려 남은 더 높은 버전 포함)은 다른 보강 버전이다.
  /// 지금 보강 버전인데 출처 속성이 하나라도 nil 이면(출처 속성이 생기기 전에 마친 행) 출처를 모르는 마침(`.sourcesUnknown`)이다.
  /// 값은 되돌리지 않는다(만료 예정 조회는 보강 상태를 보지 않으므로 알림도 그대로). `.pending` 행은 규칙 값만 담으므로
  /// 출처 nil 이어도 규칙으로 본다. 두 값이 다 있어도 마친 것으로 보지 않는다(`IndexedImage.gifticonModelFill`).
  static func modelFill(_ stored: StoredImage) -> GifticonModelFill {
    switch stored.gifticonModelVersion {
    case GifticonExtractor.modelFillVersion:
      stored.gifticonExpiryFromModel == nil || stored.gifticonRedemptionPlaceFromModel == nil ? .sourcesUnknown : .done
    case 0:
      .pending(failures: stored.gifticonModelFailures)
    default:
      .stale
    }
  }

  /// 마침이면 (지금 버전, 0), 보강하지 않음이면 (0, 실패 수) 를 쓴다. 다른 보강 버전·출처를 모르는 마침은 인덱서가 읽은 값을
  /// 되돌려 쓰지 않는다. 넘기면 보강하지 않음 (0, 0) 으로 써서 다음 읽기에서 `.pending(failures: 0)` 이다
  /// (출처는 `setGifticon` 이 넘긴 `modelFilledFields` 로 쓰므로 마침으로 쓰면 출처를 모르는 행이 마친 것으로 읽힌다).
  static func setModelFill(_ fill: GifticonModelFill, on stored: StoredImage) {
    switch fill {
    case .done:
      stored.gifticonModelVersion = GifticonExtractor.modelFillVersion
      stored.gifticonModelFailures = 0
    case let .pending(failures):
      stored.gifticonModelVersion = 0
      stored.gifticonModelFailures = failures
    case .stale, .sourcesUnknown:
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
