import Foundation
import SwiftData

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
  /// OCR 하지 않았으면 nil.
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
