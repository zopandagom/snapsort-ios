import Foundation

/// 생성일의 연·월 (기기 달력·시간대). 일본력처럼 연호가 있는 달력은 era 로 구분된다.
public struct ImageMonth: Sendable, Hashable {
  public let era: Int
  public let year: Int
  /// 1부터 센 그 달력의 월.
  public let month: Int

  public init(era: Int, year: Int, month: Int) {
    self.era = era
    self.year = year
    self.month = month
  }
}

/// 카테고리 화면의 월 섹션 하나 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 문구("날짜 없음")와 날짜 표시 형식은 화면이 정한다.
public struct ImageMonthSection: Sendable, Hashable, Identifiable {
  /// nil 이면 생성일이 없는 이미지 섹션. 늘 맨 뒤에 하나만 있다.
  public let month: ImageMonth?
  /// 최신순(같은 시각이면 식별자 순). 비어 있지 않다.
  public let assets: [ImageAsset]

  public var id: ImageMonth? {
    self.month
  }

  /// 이미지를 최신순으로 정렬한다(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순 — PhotoStore `images(in:)` 와 같은 순서).
  /// 그다음 `calendar` 의 달력·시간대로 [.era, .year, .month] 가 같은 이웃끼리 묶는다. 최신 달이 먼저, 날짜 없음 섹션이 맨 뒤다.
  /// 한 달력 안에서는 날짜 순서와 (era, 연, 월) 순서가 함께 움직이므로, 정렬한 뒤 이웃끼리만 묶으면 된다.
  /// 이미 이 순서면 정렬하지 않는다(저장소 `assets(in:)` 이 같은 순서로 돌려준다). 달력 계산은 이미지마다 한다.
  public static func sections(of assets: [ImageAsset], calendar: Calendar) -> [ImageMonthSection] {
    var sections: [ImageMonthSection] = []
    var month: ImageMonth?
    var current: [ImageAsset] = []
    let isSorted = zip(assets, assets.dropFirst()).allSatisfy { previous, next in !Self.isNewer(next, than: previous) }
    for asset in isSorted ? assets : assets.sorted(by: Self.isNewer) {
      let assetMonth = asset.creationDate.map { date in
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return ImageMonth(era: components.era ?? 0, year: components.year ?? 0, month: components.month ?? 0)
      }
      if !current.isEmpty, assetMonth != month {
        sections.append(ImageMonthSection(month: month, assets: current))
        current = []
      }
      month = assetMonth
      current.append(asset)
    }
    if !current.isEmpty {
      sections.append(ImageMonthSection(month: month, assets: current))
    }
    return sections
  }

  /// 최신순. 생성일이 없으면 맨 뒤, 같으면 식별자 순으로 고정한다.
  private static func isNewer(_ lhs: ImageAsset, than rhs: ImageAsset) -> Bool {
    switch (lhs.creationDate, rhs.creationDate) {
    case let (left?, right?) where left != right:
      left > right
    case (.some, nil):
      true
    case (nil, .some):
      false
    default:
      lhs.id < rhs.id
    }
  }
}
