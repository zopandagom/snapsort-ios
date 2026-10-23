import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 캡처 묶음 값(쇼핑몰·브랜드·대화 앱·지역)과 쇼핑·대화·지도 목록 (docs/ARCHITECTURE.md §4 저장소).
extension PhotoStore {
  func captureGroupExtractionPendingIDs() throws -> Set<ImageAsset.ID> {
    var ids: Set<ImageAsset.ID> = []
    for category in Self.captureGroupCategories {
      let rawValue = category.rawValue
      var descriptor = FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.textLinesData != nil && image.memberships.contains { $0.category == rawValue }
        }
      )
      descriptor.propertiesToFetch = [
        \.assetID, \.captureGroupRulesVersion, \.shoppingMallID, \.shoppingBrandID, \.chatAppID, \.mapRegionIDs,
      ]
      // 버전 비교를 조건에 넣지 않고 여기서 거르는 것은 영수증과 같이 해석 불가 판정(`storedCaptureGroups`)을 조건으로 쓸 수 없어서다.
      // 카테고리별로 따로 조회해 합치는 것은 여러 카테고리 조건을 한 술어에 묶는 방식을 쓰지 않으려는 것이다(결과는 같다).
      try ids
        .formUnion(self.modelContext.fetch(descriptor).filter { Self.storedCaptureGroups($0) == nil }.map(\.assetID))
    }
    return ids
  }

  func saveCaptureGroups(_ groups: [ImageAsset.ID: CaptureGroups]) throws {
    try self.write {
      let ids = Array(groups.keys)
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      for image in stored {
        // `captureGroupExtractionPendingIDs` 와 같은 조건인 행만 바꾼다. 겹친 지난 실행이 새 값을 덮거나,
        // 세 카테고리에서 빠졌다 다시 대기가 된 행에 지난 값이 붙지 않는다.
        let categories = Self.captureGroupCategories(of: image)
        guard image.textLinesData != nil,
              !categories.isEmpty,
              Self.storedCaptureGroups(image) == nil,
              let value = groups[image.assetID]
        else {
          continue
        }
        Self.setCaptureGroups(value.restricted(to: categories), on: image)
      }
    }
  }

  func captureGroupItems(in category: ImageCategory) throws -> [CaptureGroupItem] {
    guard CaptureGroupExtractor.categories.contains(category) else { return [] }
    let rawValue = category.rawValue
    let stored = try self.modelContext.fetch(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          image.memberships.contains { $0.category == rawValue }
        }
      )
    )
    return stored.sorted(by: Self.isNewer).map(Self.captureGroupItem)
  }

  /// 묶음 값을 갖는 카테고리를 고정된 순서로.
  private static let captureGroupCategories: [ImageCategory] = [.shopping, .chat, .map]

  /// 행이 든 카테고리 중 묶음 값을 갖는 것.
  private static func captureGroupCategories(of stored: StoredImage) -> Set<ImageCategory> {
    Set(stored.memberships.compactMap { ImageCategory(rawValue: $0.category) })
      .intersection(CaptureGroupExtractor.categories)
  }

  /// 저장된 캡처 묶음 값. nil 이면 추출하지 않은 것으로 본다(읽기·추출 대기·`saveCaptureGroups`·목록이 모두 이 판정을 쓴다).
  /// 버전은 맞는데 식별자를 닫힌 목록에서 풀지 못하면(모르는 몰·브랜드·앱 id, 표에 없는 지역 id, 빈 조각 `""`·`",,"`) 던지지 않고
  /// 추출하지 않은 것으로 본다. 던지면 그 행이 든 `images(in:)`·`captureGroupItems(in:)` 가 계속 실패해 사용자가 회복할 수 없고,
  /// 값은 저장된 줄로 다시 만들 수 있다(추출 대기에 들어 캡처 묶음 소급 추출이 다시 쓴다). 쓰는 쪽은 늘 목록의 값을 쓰므로
  /// 목록에서 항목을 뺀 앱 업데이트 같은 경우에만 생긴다(그때는 `rulesVersion` 도 올린다).
  static func storedCaptureGroups(_ stored: StoredImage) -> CaptureGroups? {
    // `!=` 라 앱을 되돌려 더 높은 버전이 남아도 다시 추출한다.
    guard stored.captureGroupRulesVersion == CaptureGroupExtractor.rulesVersion else {
      return nil
    }
    var mall: ShoppingMall?
    if let id = stored.shoppingMallID {
      guard let value = ShoppingMall(id: id) else { return nil }
      mall = value
    }
    var brand: ShoppingBrand?
    if let id = stored.shoppingBrandID {
      guard let value = ShoppingBrand(id: id) else { return nil }
      brand = value
    }
    var chatApp: ChatApp?
    if let id = stored.chatAppID {
      guard let value = ChatApp(rawValue: id) else { return nil }
      chatApp = value
    }
    var regions: Set<KoreanRegion> = []
    if let ids = stored.mapRegionIDs {
      for piece in ids.split(separator: ",", omittingEmptySubsequences: false) {
        guard let region = KoreanRegion(id: String(piece)) else { return nil }
        regions.insert(region)
      }
    }
    return CaptureGroups(mall: mall, brand: brand, chatApp: chatApp, regions: regions)
  }

  /// 추출함이면 지금 규칙 버전과 값(식별자)을, nil(추출 안 함)이면 (0, nil, nil, nil, nil) 을 쓴다.
  static func setCaptureGroups(_ groups: CaptureGroups?, on stored: StoredImage) {
    stored.captureGroupRulesVersion = groups == nil ? 0 : CaptureGroupExtractor.rulesVersion
    stored.shoppingMallID = groups?.mall?.id
    stored.shoppingBrandID = groups?.brand?.id
    stored.chatAppID = groups?.chatApp?.rawValue
    stored.mapRegionIDs = groups
      .flatMap { $0.regions.isEmpty ? nil : $0.regions.sorted().map(\.id).joined(separator: ",") }
  }

  /// 쇼핑·대화·지도 카테고리 행의 목록 항목. 줄을 디코딩하지 않고 OCR 상태는 `needsTextRecognition`·`textLinesData` 유무로 본다.
  /// 묶음 값이 있으면 `.extracted`, 없고 OCR 대기·추출 대기면 `.checking`, OCR 대상이 아니면 찾을 값이 없어 빈 값이다.
  private static func captureGroupItem(_ stored: StoredImage) -> CaptureGroupItem {
    let status: CaptureGroupItem.Status = if let groups = Self.storedCaptureGroups(stored) {
      .extracted(groups)
    } else if stored.needsTextRecognition || stored.textLinesData != nil {
      .checking
    } else {
      .extracted(.empty)
    }
    return CaptureGroupItem(asset: Self.imageAsset(stored), status: status)
  }
}
