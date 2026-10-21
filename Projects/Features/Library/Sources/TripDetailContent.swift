import Core
import PhotoStoreInterface

/// 여행 폴더 상세 내용.
public enum TripDetailContent: Equatable {
  case loading
  case loaded(TripDetail)
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 내용이 있을 때 실패하면 지난 내용을 둔다.
  case failed
  /// 여행 판정이 바뀌어 사진이 겹치는 여행이 없다. 여행이 돌아오면 다시 읽기에서 다시 찾는다.
  case notFound
}

/// 여행 폴더 상세에 보이는 여행 한 건.
public struct TripDetail: Equatable {
  /// 기간 캡처로 묶는 카테고리와 묶음 순서.
  static let captureCategories: [ImageCategory] = [.receipt, .map, .document]

  public let trip: Trip
  public let period: TripPeriod
  /// 지도 핀. 반올림 중심점이다. 중심점이 반올림할 수 없는 값이면 nil(지도를 보이지 않는다).
  public let mapCenter: Coordinate?
  /// 촬영순, 저장소에 있는 것만.
  public let photos: [ImageAsset]
  /// 보관함에서 지워져 저장소에 없는 여행 사진 수.
  public var missingPhotoCount: Int {
    self.trip.assetIDs.count - self.photos.count
  }

  /// 영수증 → 지도 → 문서·메모 순, 각 촬영순, 빈 묶음은 빠진다.
  public let captureGroups: [TripCaptureGroup]
}

/// 여행 기간에 만든 캡처 한 묶음.
public struct TripCaptureGroup: Equatable, Identifiable {
  public let category: ImageCategory
  /// 촬영순.
  public let assets: [ImageAsset]
  public var id: ImageCategory {
    self.category
  }
}

/// 여행 폴더 상세의 장소 이름.
public enum TripPlaceNameState: Equatable {
  /// 캐시를 읽거나 묻는 중이다.
  case loading
  case named(String)
  /// 응답은 받았지만 쓸 이름이 없다. 기간을 제목으로 쓴다.
  case unnamed
  /// 요청이 실패했거나 시한을 넘겼거나 중심점을 반올림할 수 없다. 기간을 제목으로 쓴다.
  case unavailable
}

/// 한 번 읽은 결과.
enum ReloadResult {
  /// 도중에 화면이 닫히거나 다른 진입이 시작됐다. 결과를 버린다.
  case stale
  case notFound
  case found(TripDetail, cachedName: CachedPlaceName?)
}
