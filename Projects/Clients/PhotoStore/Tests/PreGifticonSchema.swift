import Foundation
import SwiftData

/// 기프티콘 추출 값 속성(`StoredImage.gifticonRulesVersion` 등)이 생기기 전의 저장 스키마. 경량 이전 테스트가 이전 빌드의 저장 파일을 만드는 데 쓴다.
/// PR #60 머지 시점(ed47bd9)의 Impl `StoredModels.swift` 를 그대로 옮겼다. SwiftData 엔티티 이름은 타입 이름에서 오므로 Impl 과 같은 이름으로 두고,
/// 테스트 모듈의 다른 코드가 Impl 타입을 가리지 않게 이 enum 안에 둔다.
enum PreGifticonSchema {
  /// 이미지 한 장의 분류 결과. 라벨·OCR 줄은 SwiftData 의 Codable 배열 저장 대신 직접 인코딩한 Data 로 둔다.
  @Model
  final class StoredImage {
    @Attribute(.unique) var assetID: String
    var creationDate: Date?
    var latitude: Double?
    var longitude: Double?
    var pixelWidth = 0
    var pixelHeight = 0
    var isScreenshot = false
    var labelsData = Data()
    /// OCR 상태는 두 값으로 읽는다(`PhotoStore.textRecognition`):
    /// (false, nil) 대상 아님, (true, nil) 대기, (true, data) 읽음.
    /// 이 속성이 생기기 전에 저장한 행은 (false, data) 일 수 있고 읽음으로 본다(그때는 OCR 한 이미지만 data 가 있었다).
    /// 기본값이 있어 SwiftData 경량 이전이 자동으로 된다.
    var needsTextRecognition = false
    /// 읽은 OCR 줄. 대상 아님·대기면 nil.
    var textLinesData: Data?
    /// 카테고리별 개수·목록을 조회 조건으로 세기 위해 카테고리마다 한 행으로 둔다.
    @Relationship(deleteRule: .cascade, inverse: \StoredCategoryMembership.image)
    var memberships: [StoredCategoryMembership] = []

    /// 나머지 값은 `PhotoStore.save` 가 채운다.
    init(assetID: String) {
      self.assetID = assetID
    }
  }

  /// 이미지가 속한 카테고리 하나. `category` 는 `ImageCategory.rawValue`.
  @Model
  final class StoredCategoryMembership {
    var category: String
    var image: StoredImage?

    init(category: String) {
      self.category = category
    }
  }

  /// 여행 판정이 찾은 여행 하나.
  @Model
  final class StoredTrip {
    var assetIDs: [String]
    var startDate: Date
    var endDate: Date
    var centerLatitude: Double
    var centerLongitude: Double

    init(assetIDs: [String], startDate: Date, endDate: Date, centerLatitude: Double, centerLongitude: Double) {
      self.assetIDs = assetIDs
      self.startDate = startDate
      self.endDate = endDate
      self.centerLatitude = centerLatitude
      self.centerLongitude = centerLongitude
    }
  }
}
