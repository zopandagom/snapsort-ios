import Foundation

/// 벡터가 있는 대상 사진 한 장. 저장소가 돌려주고 묶기가 받는다. 사진에서 만든 벡터를 담으므로 로그에 남기지 않는다.
public struct FeaturePrintedPhoto: Sendable, Hashable, Identifiable {
  public let asset: ImageAsset
  public let featurePrint: ImageFeaturePrint

  public var id: ImageAsset.ID { self.asset.id }

  public init(asset: ImageAsset, featurePrint: ImageFeaturePrint) {
    self.asset = asset
    self.featurePrint = featurePrint
  }
}

/// 비슷한 사진 묶음 하나. 2장 이상.
public struct SimilarPhotoGroup: Sendable, Hashable, Identifiable {
  /// 첫 장(가장 이른) 식별자.
  public let id: ImageAsset.ID
  /// 생성일 오름차순(같으면 식별자 순). 촬영 순서다.
  public let photos: [ImageAsset]
  /// 남길 장. 정리 화면이 기본 선택하지 않는다.
  public let keptID: ImageAsset.ID

  public init(photos: [ImageAsset], keptID: ImageAsset.ID) {
    self.id = photos.first?.id ?? keptID
    self.photos = photos
    self.keptID = keptID
  }
}

/// 연속으로 찍은 비슷한 사진을 묶는 규칙 (docs/ARCHITECTURE.md §4 정리 도우미). 기준값은 모두 임시값이고 실기기에서 조정한다.
public enum SimilarPhotoGrouping {
  /// 생성일순 이웃 사이 최대 간격(초, 포함).
  public static let maximumGap: TimeInterval = 60
  /// 이웃 사이 최대 거리(포함).
  public static let maximumLinkDistance: Float = 0.35
  /// 묶음 첫 장과의 최대 거리(포함). 이웃끼리는 가까워도 조금씩 달라져 멀어진 사슬을 끊는다.
  public static let maximumSpreadDistance: Float = 0.5

  /// 규칙:
  /// 1. `excluding` 식별자, 생성일 없는 사진, 스크린샷을 뺀다. 같은 식별자는 처음 것만 쓴다.
  /// 2. 생성일 오름차순, 같으면 식별자 오름차순으로 둔다.
  /// 3. 앞에서부터 한 장씩, 지금 묶음의 마지막 장과 간격 ≤ `maximumGap` 이고 거리 ≤ `maximumLinkDistance` 이고
  ///    첫 장과 거리 ≤ `maximumSpreadDistance` 이면 묶음에 잇고, 아니면 새 묶음을 연다. 끊긴 뒤 이전 묶음과 다시 비교하지 않는다.
  /// 4. 2장 이상인 묶음만 남긴다.
  /// 5. 남길 장: 픽셀 수가 가장 큰 장, 같으면 최신(`ImageMonthSection.isNewer`, 같은 시각이면 식별자 작은 쪽).
  ///    `unkeepable` 식별자(이미 지워 저장소 반영을 기다리는 사진)는 남길 장으로 고르지 않는다. 묶음이 모두 그렇다면 전체에서 고른다.
  /// 6. 순서: 묶음의 마지막 장 생성일 내림차순(최근 묶음 먼저), 같으면 `id` 오름차순.
  public static func groups(
    _ photos: [FeaturePrintedPhoto],
    excluding: Set<ImageAsset.ID> = [],
    unkeepable: Set<ImageAsset.ID> = []
  ) -> [SimilarPhotoGroup] {
    var seen = Set<ImageAsset.ID>()
    let candidates = photos.filter { photo in
      photo.asset.creationDate != nil && !photo.asset.isScreenshot && !excluding.contains(photo.id)
        && seen.insert(photo.id).inserted
    }
    var chains: [[FeaturePrintedPhoto]] = []
    var current: [FeaturePrintedPhoto] = []
    for photo in self.sorted(candidates, asset: \.asset) {
      if let first = current.first, let previous = current.last, self.links(previous, first: first, to: photo) {
        current.append(photo)
        continue
      }
      if current.count >= 2 {
        chains.append(current)
      }
      current = [photo]
    }
    if current.count >= 2 {
      chains.append(current)
    }
    return chains
      .map { chain in
        let assets = chain.map(\.asset)
        let keepable = assets.filter { !unkeepable.contains($0.id) }
        return SimilarPhotoGroup(photos: assets, keptID: self.kept(keepable.isEmpty ? assets : keepable).id)
      }
      .sorted { lhs, rhs in
        let lhsDate = lhs.photos.last?.creationDate ?? .distantPast
        let rhsDate = rhs.photos.last?.creationDate ?? .distantPast
        return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.id < rhs.id
      }
  }

  /// 시간 이웃(생성일순 앞이나 뒤 이웃과 간격 ≤ `maximumGap`)이 있는 사진. 저장소가 벡터를 읽을 사진을 고른다.
  /// 묶기 규칙 3 은 이웃 간격을 요구하고 규칙 1 의 제외는 간격을 넓히기만 하므로, 이것으로 거른 입력의 `groups` 결과는 거르지 않은 입력과 같다.
  public static func linkableIDs(in assets: [ImageAsset]) -> Set<ImageAsset.ID> {
    var seen = Set<ImageAsset.ID>()
    let dated = self.sorted(
      assets.filter { $0.creationDate != nil && !$0.isScreenshot && seen.insert($0.id).inserted },
      asset: \.self
    )
    var result = Set<ImageAsset.ID>()
    for (previous, next) in zip(dated, dated.dropFirst()) {
      if let previousDate = previous.creationDate, let nextDate = next.creationDate,
         nextDate.timeIntervalSince(previousDate) <= self.maximumGap
      {
        result.insert(previous.id)
        result.insert(next.id)
      }
    }
    return result
  }

  private static func links(
    _ previous: FeaturePrintedPhoto,
    first: FeaturePrintedPhoto,
    to photo: FeaturePrintedPhoto
  ) -> Bool {
    guard let previousDate = previous.asset.creationDate, let date = photo.asset.creationDate,
          date.timeIntervalSince(previousDate) <= self.maximumGap
    else {
      return false
    }
    return previous.featurePrint.distance(to: photo.featurePrint) <= self.maximumLinkDistance
      && first.featurePrint.distance(to: photo.featurePrint) <= self.maximumSpreadDistance
  }

  /// 생성일 오름차순, 같으면 식별자 오름차순. 이미 그 순서면 정렬하지 않는다(저장소가 정렬해 넘긴다).
  private static func sorted<Element>(_ elements: [Element], asset: @escaping (Element) -> ImageAsset) -> [Element] {
    let isAscending: (Element, Element) -> Bool = { lhs, rhs in
      let lhsAsset = asset(lhs)
      let rhsAsset = asset(rhs)
      let lhsDate = lhsAsset.creationDate ?? .distantPast
      let rhsDate = rhsAsset.creationDate ?? .distantPast
      return lhsDate != rhsDate ? lhsDate < rhsDate : lhsAsset.id < rhsAsset.id
    }
    let isSorted = zip(elements, elements.dropFirst()).allSatisfy { !isAscending($1, $0) }
    return isSorted ? elements : elements.sorted(by: isAscending)
  }

  private static func kept(_ assets: [ImageAsset]) -> ImageAsset {
    let pixels: (ImageAsset) -> Int64 = { Int64(max($0.pixelWidth, 0)) * Int64(max($0.pixelHeight, 0)) }
    // 비어 있지 않은 배열만 받는다(묶음 2장 이상, 고를 장이 없으면 묶음 전체).
    return assets.min { lhs, rhs in
      let lhsPixels = pixels(lhs)
      let rhsPixels = pixels(rhs)
      return lhsPixels != rhsPixels ? lhsPixels > rhsPixels : ImageMonthSection.isNewer(lhs, than: rhs)
    } ?? assets[0]
  }
}
