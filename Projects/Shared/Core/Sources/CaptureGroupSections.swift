/// 카테고리 화면의 묶기(월별 밖) (docs/ARCHITECTURE.md §4 카테고리 화면). 선택은 저장하지 않는다(화면 일시 상태).
public enum CaptureGrouping: Sendable, Hashable, CaseIterable {
  case mall, brand, chatApp, region

  /// 그 카테고리의 묶기 순서. 쇼핑 [.mall, .brand], 대화 [.chatApp], 지도 [.region], 그 밖은 비어 있다.
  public static func groupings(for category: ImageCategory) -> [CaptureGrouping] {
    switch category {
    case .shopping: [.mall, .brand]
    case .chat: [.chatApp]
    case .map: [.region]
    default: []
    }
  }
}

/// 묶음 섹션의 키. 닫힌 목록의 값이다.
public enum CaptureGroupKey: Sendable, Hashable {
  case mall(ShoppingMall)
  case brand(ShoppingBrand)
  case chatApp(ChatApp)
  case region(KoreanRegion)

  /// 섹션 이름: 표의 이름 / `KoreanRegion.title`.
  public var title: String {
    switch self {
    case let .mall(mall): mall.name
    case let .brand(brand): brand.name
    case let .chatApp(app): app.name
    case let .region(region): region.title
    }
  }

  /// 가장 최근 이미지가 같을 때의 순서.
  var sortID: String {
    switch self {
    case let .mall(mall): "mall:\(mall.id)"
    case let .brand(brand): "brand:\(brand.id)"
    case let .chatApp(app): "chatApp:\(app.rawValue)"
    case let .region(region): "region:\(region.id)"
    }
  }
}

/// 묶기 화면의 섹션 하나. 문구("몰 모름"·"확인 중")는 화면이 정한다.
public struct CaptureGroupSection: Sendable, Hashable, Identifiable {
  public enum Kind: Sendable, Hashable {
    /// 묶음 키가 같은 이미지.
    case group(CaptureGroupKey)
    /// 추출했는데 그 묶기의 값을 못 찾았다.
    case unknown
    /// 추출 전(확인 중).
    case checking
  }

  public let kind: Kind
  /// 최신순(생성일 없는 것은 뒤, 같으면 식별자 순). 비어 있지 않다.
  public let assets: [ImageAsset]

  public var id: Kind { self.kind }
}

public enum CaptureGroupSections {
  /// 묶음마다 가장 최근 이미지가 있는 묶음부터(생성일 없는 묶음은 뒤, 같은 이미지·시각이면 `sortID` 순), 그 뒤에 모름,
  /// 맨 끝에 확인 중 섹션을 둔다. 빈 섹션은 만들지 않는다.
  /// 지역별은 한 항목을 `regions` 의 지역마다 넣는다(빈 집합이면 모름). 그 밖의 묶기는 값이 없으면 모름이다.
  public static func sections(of items: [CaptureGroupItem], grouping: CaptureGrouping) -> [CaptureGroupSection] {
    let sorted = items.sorted { ImageMonthSection.isNewer($0.asset, than: $1.asset) }
    var keyOrder: [CaptureGroupKey] = []
    var byKey: [CaptureGroupKey: [ImageAsset]] = [:]
    var unknown: [ImageAsset] = []
    var checking: [ImageAsset] = []
    for item in sorted {
      switch item.status {
      case .checking:
        checking.append(item.asset)
      case let .extracted(groups):
        let keys = Self.keys(of: groups, grouping: grouping)
        if keys.isEmpty {
          unknown.append(item.asset)
        }
        for key in keys {
          if byKey[key] == nil {
            keyOrder.append(key)
          }
          byKey[key, default: []].append(item.asset)
        }
      }
    }
    // 항목이 최신순이라 키별 첫 이미지가 그 묶음의 가장 최근 이미지다. 정렬이 안정적이지 않아도 같은 키 순서가 되도록 sortID 로 닫는다.
    let ordered = keyOrder.sorted { lhs, rhs in
      guard let left = byKey[lhs]?.first, let right = byKey[rhs]?.first else { return lhs.sortID < rhs.sortID }
      if left.id != right.id {
        return ImageMonthSection.isNewer(left, than: right)
      }
      return lhs.sortID < rhs.sortID
    }
    var sections = ordered.compactMap { key in
      byKey[key].map { CaptureGroupSection(kind: .group(key), assets: $0) }
    }
    for (kind, assets) in [(CaptureGroupSection.Kind.unknown, unknown), (.checking, checking)] where !assets.isEmpty {
      sections.append(CaptureGroupSection(kind: kind, assets: assets))
    }
    return sections
  }

  /// 그 묶기에서 이미지가 드는 묶음 키. 비면 모름.
  private static func keys(of groups: CaptureGroups, grouping: CaptureGrouping) -> [CaptureGroupKey] {
    switch grouping {
    case .mall: groups.mall.map { [.mall($0)] } ?? []
    case .brand: groups.brand.map { [.brand($0)] } ?? []
    case .chatApp: groups.chatApp.map { [.chatApp($0)] } ?? []
    case .region: groups.regions.sorted().map { .region($0) }
    }
  }
}
