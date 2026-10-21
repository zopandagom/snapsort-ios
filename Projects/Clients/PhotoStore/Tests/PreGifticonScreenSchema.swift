import Foundation
import SwiftData

/// 사용 여부·필드별 출처 속성(`StoredImage.gifticonIsUsed` 등)이 생기기 전의 저장 스키마. 경량 이전 테스트가 이전 빌드의 저장 파일을 만드는 데 쓴다.
/// PR #65 머지 시점(23c5656)의 Impl `StoredModels.swift` 를 그대로 옮겼다. SwiftData 엔티티 이름은 타입 이름에서 오므로 Impl 과 같은 이름으로 두고,
/// 테스트 모듈의 다른 코드가 Impl 타입을 가리지 않게 이 enum 안에 둔다.
enum PreGifticonScreenSchema {
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
    /// 기프티콘 추출 값은 세 속성으로 읽는다(`PhotoStore.storedGifticon`). 기프티콘으로 분류돼 글자를 읽은 행만 값을 갖는다.
    /// 추출한 규칙 버전(`GifticonExtractor.rulesVersion`). 0 이면 추출하지 않았다. 지금 버전과 다르면 추출하지 않은 것으로 읽는다.
    /// 세 속성 모두 기본값·옵셔널이라, 이 속성이 생기기 전에 저장한 행은 경량 이전으로 추출하지 않은 행이 된다.
    var gifticonRulesVersion = 0
    /// 만료일 yyyymmdd 정수(20261231). 정수 순서가 날짜 순서라 정렬·조건 조회가 된다. 못 찾음·추출 안 함이면 nil.
    var gifticonExpiryDay: Int?
    /// 교환처(OCR 텍스트 그대로). 못 찾음·추출 안 함이면 nil.
    var gifticonRedemptionPlace: String?
    /// 언어 모델 보강 상태는 두 속성으로 읽는다(`PhotoStore.modelFill`). 둘 다 기본값이라, 이 속성이 생기기 전에 저장한 행은
    /// 경량 이전으로 보강하지 않은 행(규칙 값 그대로)이 된다.
    /// 추출 값을 보강한 버전(`GifticonExtractor.modelFillVersion`). 0 이면 보강하지 않았다.
    var gifticonModelVersion = 0
    /// 보강하지 않은 행(버전 0)에서 지금 보강 버전으로 모델이 실패한 횟수. 한도(`GifticonModelFill.maximumFailures`)에 닿으면
    /// 보강을 마친 것으로 쓴다(버전을 지금 버전으로, 이 값은 0 으로).
    var gifticonModelFailures = 0
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
