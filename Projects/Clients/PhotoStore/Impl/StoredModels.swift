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
  /// 추출 값 필드별 출처. true 면 언어 모델이 채웠다(`GifticonInfo.modelFilledFields`). 추출 안 함이면 nil.
  /// 이 속성이 생기기 전에 저장한 행은 nil 이라 출처를 모른다(지금 보강 버전으로 마친 행이면 `.sourcesUnknown` 으로 읽는다,
  /// `PhotoStore.modelFill`). 옵셔널이라 경량 이전이 자동으로 된다.
  var gifticonExpiryFromModel: Bool?
  var gifticonRedemptionPlaceFromModel: Bool?
  /// 사용 여부. 사용자만 바꾸고(`setGifticonUsed`), 기프티콘 카테고리 행만 참일 수 있다(`save` 가 기프티콘에서 빠진 행은 false 로).
  /// 기본값이 있어 경량 이전으로 미사용이 된다.
  var gifticonIsUsed = false
  /// 영수증 추출 값은 다섯 속성으로 읽는다(`PhotoStore.storedReceipt`). 영수증으로 분류돼 글자를 읽은 행만 값을 갖는다.
  /// 기프티콘 추출 값과 독립이다. 모두 기본값·옵셔널이라 이 속성이 생기기 전에 저장한 행은 경량 이전으로 추출하지 않은 행이 된다.
  /// 추출한 규칙 버전(`ReceiptExtractor.rulesVersion`). 0 이면 추출하지 않았다. 지금 버전과 다르면 추출하지 않은 것으로 읽는다.
  var receiptRulesVersion = 0
  /// 가게 이름(OCR 텍스트 그대로). 못 찾음·추출 안 함이면 nil. 가게 묶음 키는 저장하지 않는다(이름에서 Core 가 계산한다).
  var receiptStoreName: String?
  /// 금액 최소 단위 정수와 통화 코드(ISO 4217). 둘 다 있거나 둘 다 nil 이다. 못 찾음·통화 모름·추출 안 함이면 nil.
  var receiptAmountMinorUnits: Int?
  var receiptCurrencyCode: String?
  /// 취소 전표. 추출 안 함이면 false.
  var receiptIsCancelled = false
  /// 캡처 묶음 값은 다섯 속성으로 읽는다(`PhotoStore.storedCaptureGroups`). 쇼핑·대화·지도로 분류돼 글자를 읽은 행만 값을 갖는다.
  /// 기프티콘·영수증 추출 값과 독립이다. 모두 기본값·옵셔널이라 이 속성이 생기기 전에 저장한 행은 경량 이전으로 추출하지 않은 행이 된다.
  /// 저장하는 값은 OCR 텍스트가 아니라 닫힌 목록의 식별자다.
  /// 추출한 규칙 버전(`CaptureGroupExtractor.rulesVersion`). 0 이면 추출하지 않았다. 지금 버전과 다르면 추출하지 않은 것으로 읽는다.
  var captureGroupRulesVersion = 0
  /// `ShoppingMall.id`. 못 찾음·추출 안 함이면 nil.
  var shoppingMallID: String?
  /// `ShoppingBrand.id`. 못 찾음·추출 안 함이면 nil.
  var shoppingBrandID: String?
  /// `ChatApp.rawValue`. 못 찾음·추출 안 함이면 nil.
  var chatAppID: String?
  /// `KoreanRegion.id` 를 정렬해 ","로 이은 값. 지역이 없거나 추출 안 함이면 nil.
  /// 배열 속성 대신 문자열로 둔 것은 기존 엔티티에 배열 속성을 더할 때의 경량 이전을 확인하지 않았고, 기본값·옵셔널 스칼라는 확인한 방식이어서다.
  var mapRegionIDs: String?
  /// 최근 스크린샷 화면에서 보관했는지. 사용자만 바꾸고(`keepInCaptureInbox`), 인덱서 `save` 는 넘긴 값이 없어 덮지 않는다.
  /// 행이 지워지면 함께 사라진다(보관함에서 빠졌다 돌아오면 새 행이라 보관하지 않은 것으로 돌아온다).
  /// 기본값이 있어 경량 이전으로 보관하지 않음이 된다.
  var isKeptInCaptureInbox = false
  /// 특징 벡터는 두 값으로 읽는다(`PhotoStore.storedFeaturePrint`). 세 상태:
  /// 대상 아님(메타데이터로 판정: 스크린샷·생성일 없음·OCR 대상, `PhotoStore.isFeaturePrintTarget`) /
  /// 대기(대상이고 버전이 `ImageFeaturePrint.version` 과 다름) / 값(버전이 같고 `featurePrint.data` 가 풀림).
  /// 벡터를 만든 버전. 0 이면 만들지 않았다. `!=` 로 비교해 앱을 되돌려 높은 버전이 남아도 다시 계산한다.
  /// 기본값이 있어 경량 이전으로 기존 행은 0(대상이면 대기)이 된다.
  var featurePrintVersion = 0
  /// 벡터 원소(3KB). 이 행을 통째로 읽는 조회(`assets(in:)`·`gifticons()`·`save` 의 기존 행 조회 등)가 장마다 3KB 를 더 읽지 않게
  /// 따로 둔다(관계는 접근할 때만 읽힌다). 행이 지워지면 함께 지워진다.
  @Relationship(deleteRule: .cascade, inverse: \StoredFeaturePrint.image)
  var featurePrint: StoredFeaturePrint?
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

/// 이미지 한 장의 특징 벡터 (`StoredImage.featurePrint`). `data` 는 `ImageFeaturePrint.floatData` 형식이다.
/// `assetID` 는 관계를 거치지 않고 식별자로 고르려고 중복으로 둔다. 새 엔티티라 경량 이전으로 빈 표가 된다.
/// 사진에서 만든 값이라 로그에 남기지 않는다.
@Model
final class StoredFeaturePrint {
  var assetID: String
  var data: Data
  var image: StoredImage?

  init(assetID: String, data: Data) {
    self.assetID = assetID
    self.data = data
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

/// 여행 중심점(반올림) 하나의 장소 캐시. 키는 반올림 좌표×100 정수 두 개이고 키마다 한 행이다(같은 키는 locale 과 함께 덮는다).
/// name nil 은 장소 항목은 왔는데 이름이 없음(`CachedPlaceName.unnamed`). 시간대는 locale 과 무관하게 쓴다.
/// 새 엔티티라 이 타입이 생기기 전의 저장 파일은 경량 이전으로 빈 캐시가 된다.
@Model
final class StoredPlaceName {
  var latitudeHundredths: Int
  var longitudeHundredths: Int
  var localeIdentifier: String
  var name: String?
  var timeZoneIdentifier: String?

  init(
    latitudeHundredths: Int,
    longitudeHundredths: Int,
    localeIdentifier: String,
    name: String?,
    timeZoneIdentifier: String?
  ) {
    self.latitudeHundredths = latitudeHundredths
    self.longitudeHundredths = longitudeHundredths
    self.localeIdentifier = localeIdentifier
    self.name = name
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}
