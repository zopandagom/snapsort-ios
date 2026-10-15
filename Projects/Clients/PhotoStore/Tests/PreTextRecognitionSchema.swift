import Foundation
import SwiftData

/// OCR 상태 속성(`StoredImage.needsTextRecognition`)이 생기기 전의 저장 스키마. 경량 이전 테스트가 이전 빌드의 저장 파일을 만드는 데 쓴다.
/// PR #49 머지 시점의 Impl `StoredModels.swift` 를 그대로 옮겼다. SwiftData 엔티티 이름은 타입 이름에서 오므로 Impl 과 같은 이름으로 두고,
/// 테스트 모듈의 다른 코드가 Impl 타입을 가리지 않게 이 enum 안에 둔다.
enum PreTextRecognitionSchema {
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
    var textLinesData: Data?
    @Relationship(deleteRule: .cascade, inverse: \StoredCategoryMembership.image)
    var memberships: [StoredCategoryMembership] = []

    init(assetID: String) {
      self.assetID = assetID
    }
  }

  @Model
  final class StoredCategoryMembership {
    var category: String
    var image: StoredImage?

    init(category: String) {
      self.category = category
    }
  }

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
